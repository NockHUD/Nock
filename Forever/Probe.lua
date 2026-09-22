-- Forever/Probe.lua
-- /nock probe: the evidence copybox for the Forever port (restriction states,
-- secret predicates, API presence, PLAYER_SWING and own-cast samples).

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local Probe = Nock:NewModule("ForeverProbe", "AceEvent-3.0")
Nock.ForeverProbe = Probe

local CAST_MAX = 20

-- Pure: data table -> copybox text. Kept API-free so it is unit-testable.
function Probe.Format(d)
  local L = {}
  L[#L + 1] = ("Nock probe  build %s  toc %s  forever %s"):format(tostring(d.build), tostring(d.toc), tostring(d.forever))
  local parts = {}
  for _, r in ipairs(d.restrictions or {}) do parts[#parts + 1] = r[1] .. "=" .. tostring(r[2]) end
  L[#L + 1] = "restrictions: " .. table.concat(parts, "  ")
  parts = {}
  for _, s in ipairs(d.secrets or {}) do parts[#parts + 1] = s[1] .. "=" .. tostring(s[2]) end
  L[#L + 1] = "secrets: " .. table.concat(parts, "  ")
  L[#L + 1] = "combat log restricted: " .. tostring(d.combatLogRestricted)
  L[#L + 1] = "missing APIs: " .. ((d.missingApis and #d.missingApis > 0) and table.concat(d.missingApis, ", ") or "none")
  parts = {}
  for _, r in ipairs(d.reads or {}) do parts[#parts + 1] = r[1] .. "=" .. tostring(r[2]) end
  L[#L + 1] = "reads: " .. table.concat(parts, "  ")
  L[#L + 1] = "UnitCastingInfo: " .. tostring(d.castingInfo)
  L[#L + 1] = ""
  L[#L + 1] = "PLAYER_SWING (gap since previous, type, duration, still for / MOVING at the release):"
  local prev
  local TYPE = { [0] = "MainHand", [1] = "OffHand", [2] = "Ranged" }
  for _, s in ipairs(d.swings or {}) do
    local gap = prev and (s.t - prev) or 0
    local move = s.moving and "MOVING" or (s.stillFor and ("still %.3f"):format(s.stillFor) or "still")
    L[#L + 1] = ("  %+6.3f  %s  %.3f  %s"):format(gap, TYPE[s.swingType] or tostring(s.swingType), tonumber(s.duration) or -1, move)
    prev = s.t
  end
  L[#L + 1] = ""
  L[#L + 1] = "auto bar cycles (bar px, fill px each half, peak fill, seconds held at final width):"
  for _, c in ipairs(d.cycles or {}) do
    local full = c.halves and (2 * c.fillPx + 2 == c.barPx) or (c.fillPx + 2 == c.barPx)
    L[#L + 1] = ("  bar=%d  fill=%d  peak=%.3f  held=%.3f  %s"):format(c.barPx, c.fillPx, c.peakP, c.held,
      full and "met" or "SHORT")
  end
  L[#L + 1] = ""
  L[#L + 1] = "own casts (t, event, spellID, castBarID):"
  for _, c in ipairs(d.casts or {}) do
    L[#L + 1] = ("  %8.3f  %s  %s  %s"):format(c.t, c.ev, tostring(c.spellID), tostring(c.castBarID or ""))
  end
  return table.concat(L, "\n")
end

function Probe:OnEnable()
  self._casts = {}
  self:RegisterEvent("UNIT_SPELLCAST_START", "OnCast")
  self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "OnCast")
  self:RegisterEvent("UNIT_SPELLCAST_STOP", "OnCast")
end

function Probe:OnCast(event, unit, castGUID, spellID, castBarID)
  if unit ~= "player" then return end
  local C = self._casts
  C[#C + 1] = { t = GetTime(), ev = event, spellID = spellID, castBarID = castBarID }
  if #C > CAST_MAX then table.remove(C, 1) end
end

function Probe:Casts()
  local out = {}
  for i = 1, #self._casts do out[i] = self._casts[i] end
  return out
end

-- "secret" / "nil" / the value as text, without ever comparing it.
local function describe(v)
  local isSecret = _G.issecretvalue
  if v == nil then return "nil" end
  if isSecret and isSecret(v) then return "secret" end
  return tostring(v)
end

local function restrictionRows()
  local rows = {}
  local RA, E = _G.C_RestrictedActions, _G.Enum and _G.Enum.AddOnRestrictionType
  if not (RA and E and RA.GetAddOnRestrictionState) then return rows end
  local STATE = { [0] = "Inactive", [1] = "Activating", [2] = "Active" }
  for _, name in ipairs({ "Combat", "Encounter", "ChallengeMode", "PvPMatch", "Map", "Chat" }) do
    local t = E[name]
    if t ~= nil then
      local okc, st = pcall(RA.GetAddOnRestrictionState, t)
      rows[#rows + 1] = { name, okc and (STATE[st] or tostring(st)) or "err" }
    end
  end
  return rows
end

local function secretRows()
  local rows = {}
  local S = _G.C_Secrets
  if not S then return rows end
  for _, fn in ipairs({ "HasSecretRestrictions", "ShouldAurasBeSecret", "ShouldCooldownsBeSecret" }) do
    if S[fn] then local okc, v = pcall(S[fn]); rows[#rows + 1] = { fn, okc and tostring(v) or "err" } end
  end
  if S.ShouldUnitSpellCastingBeSecret then
    local okc, v = pcall(S.ShouldUnitSpellCastingBeSecret, "player"); rows[#rows + 1] = { "ShouldUnitSpellCastingBeSecret(player)", okc and tostring(v) or "err" }
    okc, v = pcall(S.ShouldUnitSpellCastingBeSecret, "target"); rows[#rows + 1] = { "ShouldUnitSpellCastingBeSecret(target)", okc and tostring(v) or "err" }
  end
  if S.ShouldSpellCooldownBeSecret and Nock.Spells then
    local okc, v = pcall(S.ShouldSpellCooldownBeSecret, Nock.Spells.GCD_PROBE); rows[#rows + 1] = { "ShouldSpellCooldownBeSecret(GCD)", okc and tostring(v) or "err" }
  end
  return rows
end

local function readRows()
  local rows = {}
  local function try(label, fn, ...)
    local okc, v = pcall(fn, ...)
    rows[#rows + 1] = { label, okc and describe(v) or ("err:" .. tostring(v)) }
  end
  if _G.UnitRangedDamage then try("UnitRangedDamage", UnitRangedDamage, "player") end
  if _G.UnitAttackSpeed then try("UnitAttackSpeed", UnitAttackSpeed, "player") end
  if _G.GetRangedHaste then try("GetRangedHaste", GetRangedHaste) end
  if _G.UnitPower then try("UnitPower", UnitPower, "player", 0) end
  if _G.UnitHealth then try("UnitHealth", UnitHealth, "player") end
  if _G.UnitThreatSituation then try("UnitThreatSituation", UnitThreatSituation, "player") end
  if _G.GetUnitSpeed then try("GetUnitSpeed", GetUnitSpeed, "player") end
  if Nock.Spells then
    try("SpellCooldown(GCD).start", function() return (Nock.API.SpellCooldown(Nock.Spells.GCD_PROBE)) end)
    try("SpellCooldown(AutoShot).duration", function() return select(2, Nock.API.SpellCooldown(Nock.Spells.AUTO_SHOT)) end)
  end
  if _G.C_SwingTimer and C_SwingTimer.IsTargetWithinSwingRange and _G.Enum and Enum.PlayerSwingType then
    try("IsTargetWithinSwingRange(Ranged)", C_SwingTimer.IsTargetWithinSwingRange, Enum.PlayerSwingType.Ranged)
  end
  -- Range probes: which of these stay plain in combat decides whether CLOSE
  -- can split into dead zone and far (M3b).
  if _G.C_Spell and C_Spell.IsSpellInRange and Nock.Spells then
    try("IsSpellInRange(Raptor)", C_Spell.IsSpellInRange, Nock.Spells.RAPTOR_STRIKE, "target")
    try("IsSpellInRange(AutoShot)", C_Spell.IsSpellInRange, Nock.Spells.AUTO_SHOT, "target")
  end
  if _G.CheckInteractDistance then try("CheckInteractDistance(3)", CheckInteractDistance, "target", 3) end
  if _G.C_Item and C_Item.IsItemInRange then try("IsItemInRange(8149)", C_Item.IsItemInRange, 8149, "target") end
  -- What the swing timer and the range finder currently believe.
  try("state.targetInRange", function() return Nock.state.ranged.targetInRange end)
  try("state.rangeState", function() return Nock.state.target.rangeState end)
  return rows
end

function Probe:Report()
  local version, build, _, toc = GetBuildInfo()
  local st = Nock:GetModule("SwingTimer", true)
  local castingInfo = "n/a"
  if _G.UnitCastingInfo then
    local okc, name, _, _, startMs, endMs, _, _, _, spellID = pcall(UnitCastingInfo, "player")
    castingInfo = okc and (name and ("%s id=%s %s..%s"):format(describe(name), describe(spellID), describe(startMs), describe(endMs)) or "nil") or "err"
  end
  local clr = _G.C_CombatLog and C_CombatLog.IsCombatLogRestricted
  return Probe.Format({
    build = ("%s (%s)"):format(tostring(version), tostring(build)),
    toc = toc, forever = Nock.Flavor.forever,
    restrictions = restrictionRows(),
    secrets = secretRows(),
    combatLogRestricted = clr and tostring(select(2, pcall(clr))) or "n/a",
    missingApis = Nock.API.Missing(),
    reads = readRows(),
    castingInfo = castingInfo,
    swings = (st and st.Samples) and st:Samples() or {},
    cycles = (function()
      local rc = Nock:GetModule("ReactCluster", true)
      return (rc and rc._cycleLog) or {}
    end)(),
    casts = self:Casts(),
  })
end

-- Spellbook dump: every player spell with ID, name and rank text, so
-- Forever/Spells.lua is grown from the client, not from a wiki.
function Probe:SpellbookReport()
  local SB, E = _G.C_SpellBook, _G.Enum
  if not (SB and SB.GetNumSpellBookSkillLines and E and E.SpellBookSpellBank) then
    return "C_SpellBook not available on this client"
  end
  local L = { "spellbook (slot, spellID, name, rank):" }
  local bank = E.SpellBookSpellBank.Player
  for line = 1, SB.GetNumSpellBookSkillLines() do
    local info = SB.GetSpellBookSkillLineInfo(line)
    if info then
      L[#L + 1] = ("-- %s"):format(tostring(info.name))
      for slot = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
        local item = SB.GetSpellBookItemInfo(slot, bank)
        if item and item.spellID then
          L[#L + 1] = ("  %3d  %6d  %s  %s"):format(slot, item.spellID, tostring(item.name), Nock.API.SpellRank(item.spellID))
        end
      end
    end
  end
  return table.concat(L, "\n")
end

-- Frame stack around the React cluster: every child and the glued panels
-- with shown state, height and top edge, for layering/seam questions.
function Probe:FramesReport()
  local L = {}
  local function num(v) return type(v) == "number" and ("%.3f"):format(v) or tostring(v) end
  local pw, ph
  if _G.GetPhysicalScreenSize then pw, ph = _G.GetPhysicalScreenSize() end
  local uip = _G.UIParent
  L[#L + 1] = ("screen: physical=%sx%s  UIParent scale=%s eff=%s  UIParent h=%s"):format(
    tostring(pw), tostring(ph), uip and num(uip:GetScale()) or "?",
    uip and num(uip:GetEffectiveScale()) or "?", uip and num(uip:GetHeight()) or "?")
  L[#L + 1] = "frames (name, shown, height, top | px per unit, top in px, bottom in px, anchor):"
  local function row(f, label)
    if not f then L[#L + 1] = ("  %s: missing"):format(label); return end
    local okh, h = pcall(f.GetHeight, f)
    local okt, top = pcall(f.GetTop, f)
    local okb, bot = pcall(f.GetBottom, f)
    local ps = Nock.UI and Nock.UI.PixelScale and Nock.UI.PixelScale(f)
    local okp, point, _, relPoint, x, y = pcall(f.GetPoint, f, 1)
    local anchor = okp and point and ("%s/%s %s,%s"):format(tostring(point), tostring(relPoint), num(x), num(y)) or "?"
    L[#L + 1] = ("  %-22s shown=%s h=%s top=%s | ps=%s topPx=%s botPx=%s  %s"):format(label,
      tostring(f:IsShown()), okh and num(h) or "?", okt and num(top) or "?",
      num(ps), (okt and top and ps) and num(top * ps) or "?",
      (okb and bot and ps) and num(bot * ps) or "?", anchor)
  end
  row(_G.NockHUD, "NockHUD")
  local cluster = _G.NockReactCluster
  row(cluster, "NockReactCluster")
  if cluster then
    for i, c in ipairs({ cluster:GetChildren() }) do
      row(c, c:GetName() or ("child" .. i))
    end
  end
  local strip = _G.NockReactRangeStrip
  if strip then
    for i, c in ipairs({ strip:GetChildren() }) do
      row(c, c:GetName() or ("strip" .. i))
    end
  end
  row(_G.NockReactCastBar, "NockReactCastBar")
  row(_G.NockReactBuffs, "NockReactBuffs")
  row(_G.NockReactCDSlot1, "NockReactCDSlot1")
  return table.concat(L, "\n")
end

function Probe:Show(which)
  local text
  if which == "spells" then text = self:SpellbookReport()
  elseif which == "frames" then text = self:FramesReport()
  else text = self:Report() end
  if Nock.UI and Nock.UI.ShowCopyBox then Nock.UI.ShowCopyBox(text) else Nock:Print(text) end
end
