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
-- Seconds both auto-attacks may be off on a live hostile target before the
-- "not attacking" square fires: a retarget or a swap to melee never blinks it.
local NOT_ATTACKING_GRACE = 1.5
-- Seconds the target may sit in a zone the attack in use cannot reach before
-- the "not in range" square fires: a step through the dead zone never blinks.
local NOT_IN_RANGE_GRACE = 1.0
-- Seconds a living pet may stand without a target in combat before the
-- "pet idle" square fires: the attack order lands a beat after the pull.
local PET_IDLE_GRACE = 1.5
local PET_ATTACK_ICON = 132152  -- Ability_GhoulFrenzy, the pet Attack command
-- The zones the range finder publishes that each attack cannot reach.
local RANGED_MISSES = { CLOSE = "DEAD ZONE", LONG = "RANGE" }
local MELEE_MISSES  = { CLOSE = "DEAD ZONE" }

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
--   reads.rangedOn, reads.meleeOn   the two auto-attack toggles
--   reads.targetHostile             a live, attackable target
--   reads.zone                      the range finder's zone (MELEE/CLOSE/SWEET/LONG)
--   reads.petTarget                 the pet has a target (nil = secret)
--   reads.now
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
  if reads.loneWolf == true then return nil end   -- no pet is the build, not a mistake
  return warn("petMissing", "amber", spellIcon(Nock.Spells.PET.CALL_PET) or 132161, "NO PET", nil)
end

function Checks.petUnhappy(reads)
  if not isEnabled("warnPetUnhappyEnabled") then return nil end
  if reads.petExists ~= true or reads.petDead == true or reads.happiness ~= 1 then return nil end
  return warn("petUnhappy", "amber", spellIcon(Nock.Spells.PET.FEED_PET) or 132165, "FEED", nil)
end

-- Both auto-attacks off in combat on a live hostile target, past the grace.
-- The grace runs only while the condition holds; anything else resets it.
local idleSince
function Checks.notAttacking(reads)
  local idle = isEnabled("warnNotAttackingEnabled") and reads.inCombat == true
    and reads.targetHostile == true and reads.rangedOn ~= true and reads.meleeOn ~= true
  if not idle then idleSince = nil; return nil end
  local now = reads.now or 0
  if not idleSince then idleSince = now end
  if now - idleSince < NOT_ATTACKING_GRACE then return nil end
  return warn("notAttacking", "red", spellIcon(Nock.Spells.AUTO_SHOT) or 132222, "ATTACK", nil)
end

-- The target sits where the attack in use cannot reach it: shooting, the
-- dead zone and out of range; meleeing, the dead zone. Auto Shot on decides
-- the ranged reading unless a melee swing can land (both on in reach).
local farSince
function Checks.notInRange(reads)
  local text
  if isEnabled("warnNotInRangeEnabled") and reads.inCombat == true and reads.targetHostile == true then
    if reads.rangedOn == true then
      text = RANGED_MISSES[reads.zone]
      if reads.meleeOn == true and reads.zone == "MELEE" then text = nil end
    elseif reads.meleeOn == true then
      text = MELEE_MISSES[reads.zone]
    end
  end
  if not text then farSince = nil; return nil end
  local now = reads.now or 0
  if not farSince then farSince = now end
  if now - farSince < NOT_IN_RANGE_GRACE then return nil end
  return warn("notInRange", "amber", spellIcon(Nock.Spells.AUTO_SHOT) or 132222, text, nil)
end

-- A living pet with no target in combat (TBC's rule, same key): it is not
-- attacking, or about to. A secret answer stays quiet.
local petIdleSince
function Checks.petAttack(reads)
  local idle = isEnabled("warnPetAttackEnabled") and reads.inCombat == true
    and reads.petExists == true and reads.petDead ~= true and reads.petTarget == false
  if not idle then petIdleSince = nil; return nil end
  local now = reads.now or 0
  if not petIdleSince then petIdleSince = now end
  if now - petIdleSince < PET_IDLE_GRACE then return nil end
  return warn("petAttack", "amber", PET_ATTACK_ICON, "PET IDLE", nil)
end

-- Growl on autocast inside a dungeon or raid: the pet taunts mobs off the
-- tank. Open world stays quiet (solo, Growl autocast is what you want).
function Checks.petGrowl(reads)
  if not isEnabled("warnPetGrowlEnabled") then return nil end
  if reads.inInstance ~= true or reads.petExists ~= true or reads.petDead == true then return nil end
  if reads.growlAutocast ~= true then return nil end
  return warn("petGrowl", "amber", spellIcon(Nock.Spells.GROWL) or 132270, "GROWL", nil)
end

Warnings.ORDER = { Checks.ammo, Checks.petDead, Checks.petMissing, Checks.petUnhappy, Checks.notAttacking, Checks.notInRange, Checks.petAttack, Checks.petGrowl }

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
  -- Plain true/false only; a secret (or no pet) reads nil. Written out in
  -- full: `x and false or nil` would turn the idle answer into nil.
  r.petTarget = nil
  if r.petExists and _G.UnitExists then
    local pt = P(UnitExists("pettarget"))
    if pt == true then r.petTarget = true elseif pt == false then r.petTarget = false end
  end
  local PI = _G.C_PetInfo
  r.happiness = r.petExists and PI and PI.GetPetHappiness and P(PI.GetPetHappiness()) or nil
  if type(r.happiness) ~= "number" then r.happiness = nil end
  r.inCombat = state.player and state.player.inCombat == true
  r.callPetKnown = self:CallPetKnown()
  r.loneWolf = self:LoneWolf(r.inCombat)
  -- The toggles and the target come from state: the swing timer keeps both
  -- auto-attack edges, the range finder the target's presence and side.
  r.rangedOn = state.ranged and state.ranged.repeating == true
  r.meleeOn  = state.melee and state.melee.attacking == true
  local t = state.target
  r.targetHostile = t and t.exists == true and t.alive == true and t.friendly == false
  r.zone = t and t.rangeState or nil
  r.inInstance = self:InInstance()
  r.growlAutocast = nil
  if r.inInstance and r.petExists then r.growlAutocast = self:GrowlAutocast() end
  r.now = GetTime()
  return r
end

-- A dungeon or raid instance (instance-based, not group-based: the same rule
-- as Nock.IsInInstance on TBC).
function Warnings:InInstance()
  if not _G.IsInInstance then return false end
  local _, kind = IsInInstance()
  kind = P(kind)
  return kind == "party" or kind == "raid"
end

-- Growl's pet-bar slot, found by its localized NAME (every rank shares it),
-- and that slot's autocast flag (6th return). nil when unknown or secret.
function Warnings:GrowlAutocast()
  if not _G.GetPetActionInfo then return nil end
  local growl = P(Nock.API.SpellName and Nock.API.SpellName(Nock.Spells.GROWL))
  if type(growl) ~= "string" then return nil end
  for i = 1, (_G.NUM_PET_ACTION_SLOTS or 10) do
    local name, _, _, _, _, autoCastEnabled = GetPetActionInfo(i)
    if P(name) == growl then
      local on = P(autoCastEnabled)
      if on == nil then return nil end
      return on and true or false
    end
  end
  return nil
end

-- Lone Wolf talented? Forever's talents are the retail-style trait tree
-- (C_ClassTalents + C_Traits; the classic talent APIs answer nothing here,
-- probed 2026-09-26): the active loadout's node holding the talent's spell
-- id, rank > 0. The spellbook and an aura on you are the fallbacks. Talents
-- only change out of combat, so the answer is read out of combat (at most
-- every LONE_WOLF_RECHECK seconds) and held through a fight. `how` names the
-- path that matched, for `/nock probe lonewolf`.
local LONE_WOLF_RECHECK = 5
function Warnings.LoneWolfFrom(id, traitRank, spellKnown, auraBySpell)
  if type(id) ~= "number" then return false end
  local r = traitRank and traitRank(id)
  if type(r) == "number" and r > 0 then return true, "talent" end
  if spellKnown and spellKnown(id) == true then return true, "spellbook" end
  if auraBySpell and auraBySpell(id) then return true, "aura" end
  return false
end

-- The rank of the active loadout's node whose entry is `spellID`. The node
-- is found once per loadout (a 50-node walk) and then read directly.
local traitNode = { config = nil, node = nil }
function Warnings.TraitRank(spellID, CT, T)
  if not (CT and CT.GetActiveConfigID and T and T.GetConfigInfo and T.GetTreeNodes and T.GetNodeInfo
          and T.GetEntryInfo and T.GetDefinitionInfo) then return nil end
  local okc, config = pcall(CT.GetActiveConfigID)
  if not okc or not config then return nil end
  if traitNode.config ~= config then
    traitNode.config, traitNode.node = config, nil
    local oki, info = pcall(T.GetConfigInfo, config)
    for _, tree in ipairs(oki and type(info) == "table" and info.treeIDs or {}) do
      local okn, nodes = pcall(T.GetTreeNodes, tree)
      for _, nodeID in ipairs(okn and type(nodes) == "table" and nodes or {}) do
        local okd, node = pcall(T.GetNodeInfo, config, nodeID)
        for _, entryID in ipairs(okd and type(node) == "table" and node.entryIDs or {}) do
          local oke, entry = pcall(T.GetEntryInfo, config, entryID)
          local def = oke and type(entry) == "table" and entry.definitionID
          local okf, d = false, nil
          if def then okf, d = pcall(T.GetDefinitionInfo, def) end
          if okf and type(d) == "table" and d.spellID == spellID then traitNode.node = nodeID end
        end
        if traitNode.node then break end
      end
      if traitNode.node then break end
    end
  end
  if not traitNode.node then return nil end
  local okr, node = pcall(T.GetNodeInfo, config, traitNode.node)
  return okr and type(node) == "table" and P(node.activeRank) or nil
end
function Warnings.ResetTraitCache() traitNode.config, traitNode.node = nil, nil end

function Warnings:LoneWolf(inCombat)
  local now = GetTime()
  if inCombat or (self._loneWolfAt and now - self._loneWolfAt < LONE_WOLF_RECHECK) then
    return self._loneWolf == true
  end
  self._loneWolfAt = now
  local AC, SB = Nock.AuraCache, _G.C_SpellBook
  self._loneWolf, self._loneWolfHow = Warnings.LoneWolfFrom(Nock.Spells.LONE_WOLF,
    function(id) return Warnings.TraitRank(id, _G.C_ClassTalents, _G.C_Traits) end,
    SB and SB.IsSpellKnown and function(id) local okk, k = pcall(SB.IsSpellKnown, id); return okk and k end,
    AC and AC.BySpell and function(id) return AC.BySpell("player", id) end)
  return self._loneWolf == true
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
    logic       = "Fires when:\n• You are in combat\n• No pet is out\n• You know Call Pet\n• You do not have Lone Wolf talented\n\nQuiet out of combat, so a dismissed pet in town never nags.",
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
  {
    key         = "notAttacking",
    category    = "combat",
    name        = "Not attacking",
    severity    = "red",
    enabledKey  = "warnNotAttackingEnabled",
    iconFn      = function() return spellIcon(Nock.Spells.AUTO_SHOT) or 132222 end,
    description = "You have a live hostile target and neither auto-attack is on.",
    logic       = "Fires when:\n• You are in combat\n• Your target is alive and attackable\n• Auto Shot is off and melee auto-attack is off\n• That has held for 1.5 s\n\nClears the moment either auto-attack is on, the target dies or combat ends.",
  },
  {
    key         = "notInRange",
    category    = "combat",
    name        = "Not in range",
    severity    = "amber",
    enabledKey  = "warnNotInRangeEnabled",
    iconFn      = function() return spellIcon(Nock.Spells.AUTO_SHOT) or 132222 end,
    description = "Your target sits where the attack you are using cannot reach it.",
    logic       = "Fires when:\n• You are in combat on a live, attackable target\n• Auto Shot is on and the target is in the dead zone (DEAD ZONE) or out of range (RANGE)\n• or only melee auto-attack is on and the target is in the dead zone\n• That has held for 1 s\n\nQuiet in melee reach while a melee swing can land, and quiet when no auto-attack is on (the Not attacking square covers that).",
  },
  {
    key         = "petAttack",
    category    = "pet",
    name        = "Pet not attacking",
    severity    = "amber",
    enabledKey  = "warnPetAttackEnabled",
    iconFn      = function() return PET_ATTACK_ICON end,
    description = "Your pet is standing idle in combat.",
    logic       = "Fires when:\n• You are in combat\n• A living pet is out\n• It has no target\n• That has held for 1.5 s\n\nSend it in with the pet Attack command or a /petattack macro; the square clears the moment it has a target.",
  },
  {
    key         = "petGrowl",
    category    = "pet",
    name        = "Pet Growl on in a dungeon or raid",
    severity    = "amber",
    enabledKey  = "warnPetGrowlEnabled",
    iconFn      = function() return spellIcon(Nock.Spells.GROWL) or 132270 end,
    description = "Your pet's Growl is on autocast inside a dungeon or raid: turn it off so the pet does not taunt mobs off the tank.",
    logic       = "Fires when:\n• You are inside a dungeon or raid instance\n• A living pet is out\n• Growl is on the pet bar with autocast on\n\nIn and out of combat, so it shows before the pull. Quiet in the open world, where Growl on autocast is what you want solo. Matched by Growl's name, so every rank counts.",
  },
}
