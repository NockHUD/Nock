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
  -- Press-side edges: Multi-Shot fires no START here, only SUCCEEDED, so
  -- these say when the press lands and whether SUCCEEDED is the release.
  self:RegisterEvent("UNIT_SPELLCAST_SENT", "OnCastSent")
  self:RegisterEvent("UNIT_SPELLCAST_FAILED", "OnCast")
  self:RegisterEvent("UNIT_SPELLCAST_FAILED_QUIET", "OnCast")
  self:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED", "OnCast")
  self:RegisterEvent("CURRENT_SPELL_CAST_CHANGED", "OnAttackToggle")
  -- The melee auto-attack toggle pair (the "not attacking" warning's feed):
  -- logged with the casts so one report shows whether they fire here.
  self:RegisterEvent("PLAYER_ENTER_COMBAT", "OnAttackToggle")
  self:RegisterEvent("PLAYER_LEAVE_COMBAT", "OnAttackToggle")
  -- The pet's own pair, the fallback feed for the pet-idle warning should
  -- UnitExists("pettarget") turn out secret.
  self:RegisterEvent("PET_ATTACK_START", "OnAttackToggle")
  self:RegisterEvent("PET_ATTACK_STOP", "OnAttackToggle")
end

function Probe:OnAttackToggle(event)
  local C = self._casts
  C[#C + 1] = { t = GetTime(), ev = event }
  if #C > CAST_MAX then table.remove(C, 1) end
end

function Probe:OnCast(event, unit, castGUID, spellID, castBarID)
  if unit ~= "player" then return end
  local C = self._casts
  C[#C + 1] = { t = GetTime(), ev = event, spellID = spellID, castBarID = castBarID }
  if #C > CAST_MAX then table.remove(C, 1) end
end

function Probe:OnCastSent(event, unit, target, castGUID, spellID)
  self:OnCast(event, unit, castGUID, spellID)
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
  -- The auto-attack toggles: the events' state and the polled fallback.
  if _G.IsCurrentSpell and Nock.Spells then
    try("IsCurrentSpell(Attack)", IsCurrentSpell, Nock.Spells.ATTACK)
    try("IsCurrentSpell(AutoShot)", IsCurrentSpell, Nock.Spells.AUTO_SHOT)
  end
  if _G.UnitExists then try("UnitExists(pettarget)", UnitExists, "pettarget") end
  try("state.ranged.repeating", function() return Nock.state.ranged.repeating end)
  try("state.melee.attacking", function() return Nock.state.melee.attacking end)
  try("state.target.exists/alive/friendly", function() local t = Nock.state.target; return ("%s/%s/%s"):format(tostring(t.exists), tostring(t.alive), tostring(t.friendly)) end)
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

-- How the aura cache stored one player aura, against the id the catalog
-- expects: the value's type and secrecy, whether it equals the id, whether
-- the id lookup finds it and whether the buff row carries it.
function Probe.AuraReport(a, id, hit, inRow)
  local L = {}
  local sid = a.spellId
  L[#L + 1] = ("aura %s"):format(tostring(a.name))
  L[#L + 1] = ("  spellId: %s %s"):format(type(sid), tostring(sid))
  L[#L + 1] = ("  secret: %s"):format(tostring(_G.issecretvalue and issecretvalue(sid) or false))
  L[#L + 1] = ("  == %s: %s"):format(tostring(id), tostring(sid == id))
  L[#L + 1] = ("  BySpell(%s): %s"):format(tostring(id), hit and "hit" or "miss")
  L[#L + 1] = ("  duration: %s  expirationTime: %s  instance: %s  icon: %s"):format(
    tostring(a.duration), tostring(a.expirationTime), tostring(a.auraInstanceID), tostring(a.icon))
  L[#L + 1] = ("  ledger row: %s"):format(inRow and "yes" or "no")
  return table.concat(L, "\n")
end

-- The buff row's state at the same moment: why a ledger entry may not draw.
function Probe.RowState()
  local L = {}
  local R = Nock.GetModule and Nock:GetModule("ReactBuffs", true)
  if not R then L[#L + 1] = "row: no ReactBuffs module"; return table.concat(L, "\n") end
  local f = R.frame
  local function b(v) return tostring(v) end
  local okE, en = pcall(function() return R:IsEnabled() end)
  L[#L + 1] = ("row enabled: %s"):format(okE and b(en) or "err")
  if f then
    local parent = f.GetParent and f:GetParent()
    L[#L + 1] = ("  shown: %s  visible: %s  alpha: %s  size: %sx%s  parent shown: %s"):format(
      b(f:IsShown()), b(f:IsVisible()), b(f:GetAlpha()), b(f:GetWidth()), b(f:GetHeight()),
      parent and b(parent:IsShown()) or "nil")
  else
    L[#L + 1] = "  no frame"
  end
  L[#L + 1] = ("  items: %s  lastN: %s"):format(b(R._items and R._items.n), b(R._lastN))
  local s = R._slots and R._slots[1]
  if s then
    L[#L + 1] = ("  slot1 shown: %s  texture: %s"):format(b(s:IsShown()), b(s.icon and s.icon.GetTexture and s.icon:GetTexture()))
  end
  local p = Nock.db and Nock.db.profile or {}
  local pl = Nock.state and Nock.state.player or {}
  L[#L + 1] = ("  inCombat: %s  hideOoc: %s  opacityOoc: %s  reactBuffRows: %s  wizardHides: %s"):format(
    b(pl.inCombat), b(p.hideOoc), b(p.opacityOoc), b(p.reactBuffRows), b(Nock.WizardHides and Nock.WizardHides("react.buffs")))
  local hud = Nock.parentFrame
  if hud then L[#L + 1] = ("  hud shown: %s  alpha: %s"):format(b(hud:IsShown()), b(hud:GetAlpha())) end
  return table.concat(L, "\n")
end

-- Poll the cache for a named player aura for two minutes (a 12 s proc can't
-- be caught by hand) and open the report the moment it shows.
function Probe:WatchAura(name, id)
  local T = _G.C_Timer
  if not (T and T.NewTicker) then Nock:Print("No ticker on this client."); return end
  T.NewTicker(0.5, function(t)
    local AC = Nock.AuraCache
    local a = AC and AC.ByName and AC.ByName("player", name)
    if not a then return end
    t:Cancel()
    local hit = (AC.BySpell and AC.BySpell("player", id)) and true or false
    local inRow = false
    local lb = Nock.state and Nock.state.ledgerBuffs
    for i = 1, (lb and lb.n or 0) do if lb[i].icon == a.icon then inRow = true end end
    local text = Probe.AuraReport(a, id, hit, inRow) .. "\n" .. Probe.RowState()
    if Nock.UI and Nock.UI.ShowCopyBox then Nock.UI.ShowCopyBox(text) else Nock:Print(text) end
  end, 240)
  Nock:Print(("Watching for %s for two minutes."):format(name))
end

-- The aura-container spike (spec: Blizzard `CustomAuraContainerTemplate`
-- as the row for "everything else"). The client renders the auras itself,
-- so procs and outside buffs can show in combat without the addon reading
-- a secret. This builds one row of the player's own helpful auras under the
-- HUD and reports which steps the client accepted; what it draws is the
-- in-game answer. Throwaway until proven.
local CONTAINER_TILE = 28

-- A CustomAuraButtonTemplate button draws NOTHING until the addon hands it
-- regions: the icon texture and the cooldown swipe here (the client fills
-- them; the addon never reads them). Done once per button.
local function styleAuraButton(b)
  if b._nockStyled then return end
  b._nockStyled = true
  b:SetSize(CONTAINER_TILE, CONTAINER_TILE)
  -- a green square behind every button: shows where the client puts a
  -- button even when it fills no icon
  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(b)
  bg:SetColorTexture(0.2, 0.6, 0.2, 0.5)
  local tex = b:CreateTexture(nil, "ARTWORK")
  tex:SetAllPoints(b)
  tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b:SetIcon(tex)
  local cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
  cd:SetAllPoints(b)
  b:SetDurationCooldown(cd)
end

function Probe:ContainerSpike()
  local L = {}
  local function step(name, fn)
    local okc, err = pcall(fn)
    L[#L + 1] = ("  %s: %s"):format(name, okc and "ok" or ("err " .. tostring(err)))
    return okc
  end
  local c = self._container
  if not c then
    L[#L + 1] = "aura container (new):"
    if not step("CreateFrame", function()
      c = CreateFrame("AuraContainer", "NockProbeAuraContainer", UIParent, "CustomAuraContainerTemplate")
    end) then return table.concat(L, "\n") end
    self._container = c
    step("SetPoint", function()
      c:SetPoint("TOP", UIParent, "CENTER", 0, -160)
      c:SetSize(8 * (CONTAINER_TILE + 2), CONTAINER_TILE)
      c:SetFrameStrata("HIGH")
      -- a dark strip so the container's spot is visible even when empty
      local bg = c:CreateTexture(nil, "BACKGROUND")
      bg:SetAllPoints(c)
      bg:SetColorTexture(0, 0, 0, 0.6)
      -- and a plain marker frame at the same spot that no layout can
      -- resize: if THIS is not on screen, the spot is wrong, not the container
      local m = CreateFrame("Frame", nil, UIParent)
      m.marker = true
      m:SetPoint("TOP", UIParent, "CENTER", 0, -160)
      m:SetSize(8 * (CONTAINER_TILE + 2), 4)
      m:SetFrameStrata("HIGH")
      local mt = m:CreateTexture(nil, "OVERLAY")
      mt:SetAllPoints(m)
      mt:SetColorTexture(1, 0.2, 0.2, 0.9)
      m:Show()
    end)
    -- the template's flow layout; the enums live in AnchorUtil (dumped below)
    local AU = _G.AnchorUtil or {}
    step("SetFlowLayoutAxis", function()
      c:SetFlowLayoutAxis(AU.FlowLayoutAxis and AU.FlowLayoutAxis.Horizontal or 1)
    end)
    step("SetFlowLayoutGrowthDirection", function()
      local D = AU.FlowDirection or {}
      c:SetFlowLayoutGrowthDirection(D.Right or 2, D.Down or 4)
    end)
    step("SetFlowLayoutAnchorPoint", function() c:SetFlowLayoutAnchorPoint("TOPLEFT") end)
    step("SetUnit", function() c:SetUnit("player") end)
    step("AddAuraGroup", function()
      c:AddAuraGroup("own", "HELPFUL|PLAYER", { maxFrameCount = 8, initializeFrame = styleAuraButton })
    end)
    step("SetAuraGroupLayout", function()
      c:SetAuraGroupLayout("own", { elementWidth = CONTAINER_TILE, elementHeight = CONTAINER_TILE, elementSpacing = 2 })
    end)
    step("SetEnabled", function() c:SetEnabled(true) end)
    step("Show", function() c:Show() end)
  else
    L[#L + 1] = "aura container (existing):"
  end
  step("UpdateAllAuras", function() c:UpdateAllAuras() end)
  local n = 0
  step("GetAuraGroupFrame", function()
    -- The frames exist for the addon; their shown state is a secret boolean
    -- (measured 2026-09-23), so count frames, never read them.
    for i = 1, 8 do
      local f = c:GetAuraGroupFrame("own", i)
      if f then n = n + 1; styleAuraButton(f) end
    end
  end)
  L[#L + 1] = ("  group frames: %d"):format(n)
  -- What the container and its first button say about themselves (every
  -- read guarded: some of it is secret).
  local function geo(label, f)
    local okg, line = pcall(function()
      return ("%s: shown %s  visible %s  alpha %s  size %sx%s  left %s  top %s  strata %s  level %s  scale %s"):format(
        label, tostring(f:IsShown()), tostring(f:IsVisible()), tostring(f:GetAlpha()),
        tostring(f:GetWidth()), tostring(f:GetHeight()), tostring(f:GetLeft()), tostring(f:GetTop()),
        tostring(f:GetFrameStrata()), tostring(f:GetFrameLevel()), tostring(f:GetEffectiveScale()))
    end)
    L[#L + 1] = "  " .. (okg and line or (label .. ": err " .. tostring(line)))
  end
  geo("container", c)
  local b1 = n > 0 and c:GetAuraGroupFrame("own", 1) or nil
  if b1 then geo("button1", b1) end
  -- The layout enums, as the client has them, so the next round guesses less.
  local AU = _G.AnchorUtil
  if type(AU) == "table" then
    for k, v in pairs(AU) do
      if type(v) == "table" and (k:find("Flow") or k:find("Direction") or k:find("Axis")) then
        local parts = {}
        for mk, mv in pairs(v) do parts[#parts + 1] = tostring(mk) .. "=" .. tostring(mv) end
        table.sort(parts)
        L[#L + 1] = ("  AnchorUtil.%s: %s"):format(k, table.concat(parts, " "))
      end
    end
  else
    L[#L + 1] = "  AnchorUtil: missing"
  end
  L[#L + 1] = "  look under the screen centre: a dark strip; green squares where the client places a button; icons if it fills them."
  return table.concat(L, "\n")
end

-- The range-ladder probe (Range Finder ladder, 2026-09-24): which range
-- checks answer on Forever, whether they stay plain in combat, and in which
-- order they flip as the hunter walks away from a target. Records a row every
-- time any reading changes, until stopped. TBC's ladder items first (yards
-- from the reference WA), then other LibRangeCheck candidates, the four
-- interact distances, and the hunter's spells. Throwaway evidence tooling.
local RANGE_ITEMS = {
  { 8149, "~5 melee" }, { 34368, "~8" }, { 32321, "~10" }, { 33069, "~15" },
  { 10645, "~20" }, { 24268, "~25" }, { 13289, "~25" }, { 835, "~30" },
  { 7734, "~30" }, { 18904, "~35" }, { 4945, "~40" }, { 28767, "~40" },
}
local RANGE_SPELLS = {
  { 75, "Auto Shot" }, { 2973, "Raptor Strike" }, { 2974, "Wing Clip" }, { 1495, "Mongoose Bite" },
  { 19503, "Scatter Shot" }, { 5116, "Concussive Shot" }, { 3044, "Arcane Shot" }, { 1978, "Serpent Sting" },
  { 19434, "Aimed Shot" }, { 2643, "Multi-Shot" }, { 1130, "Hunter's Mark" },
}
local RANGE_MAX_ROWS = 500

-- One reading as a short token: T / F / nil / S (secret) / E (the call threw).
local function rangeToken(okc, v)
  if not okc then return "E" end
  if v == nil then return "-" end
  local isSecret = _G.issecretvalue
  if isSecret and isSecret(v) then return "S" end
  if v == true or v == 1 then return "T" end
  if v == false or v == 0 then return "F" end
  return tostring(v)
end

-- Every reading for the current target, in a fixed column order. Probed only
-- for a live hostile target: in combat the item and interact checks are
-- protected on a unit you cannot attack.
function Probe:RangeReadings(out)
  local P = Nock.Flavor.Plain
  local okx, can = pcall(function()
    return P(UnitExists("target")) == true and P(UnitIsDeadOrGhost("target")) == false
       and P(UnitCanAttack("player", "target")) == true
  end)
  if not (okx and can) then return false end
  local CI, CS = _G.C_Item, _G.C_Spell
  local n = 0
  for _, it in ipairs(RANGE_ITEMS) do
    n = n + 1
    if CI and CI.IsItemInRange then out[n] = rangeToken(pcall(CI.IsItemInRange, it[1], "target")) else out[n] = "E" end
  end
  for i = 1, 4 do
    n = n + 1
    if _G.CheckInteractDistance then out[n] = rangeToken(pcall(CheckInteractDistance, "target", i)) else out[n] = "E" end
  end
  for _, sp in ipairs(RANGE_SPELLS) do
    n = n + 1
    -- by name first (ranks are separate spells here), then by id
    local tok = "E"
    if CS and CS.IsSpellInRange then
      local nm = P(Nock.API and Nock.API.SpellName and Nock.API.SpellName(sp[1]))
      if type(nm) == "string" then tok = rangeToken(pcall(CS.IsSpellInRange, nm, "target")) end
      if tok == "-" or tok == "E" then
        local t2 = rangeToken(pcall(CS.IsSpellInRange, sp[1], "target"))
        if t2 ~= "-" and t2 ~= "E" then tok = t2 .. "#" end   -- '#': only the id answered
      end
    end
    out[n] = tok
  end
  return true
end

local function rangeHeader()
  local L = {}
  L[#L + 1] = "Nock probe range  (T in range, F out, - no answer, S secret, E error; # = id answered, name did not)"
  L[#L + 1] = "columns:"
  local c = 0
  for _, it in ipairs(RANGE_ITEMS) do c = c + 1; L[#L + 1] = ("  %2d item %d %s"):format(c, it[1], it[2]) end
  for i = 1, 4 do c = c + 1; L[#L + 1] = ("  %2d CheckInteractDistance %d"):format(c, i) end
  for _, sp in ipairs(RANGE_SPELLS) do c = c + 1; L[#L + 1] = ("  %2d spell %d %s"):format(c, sp[1], sp[2]) end
  L[#L + 1] = "rows (seconds since start, C = in combat, then columns 1..n; a row only when something changed):"
  return L
end

function Probe:RangeRecord(rest)
  rest = rest or ""
  local r = self._range
  local note = rest:match("^mark%s*(.*)$")
  if note then
    if not r then Nock:Print("Range probe is not running: /nock probe range"); return end
    r.rows[#r.rows + 1] = ("  %7.2f  -- mark: %s"):format(GetTime() - r.t0, note ~= "" and note or "(mark)")
    Nock:Print("Range probe: marked.")
    return
  end
  if r then
    -- stop: open the log
    r.ticker:Cancel()
    self._range = nil
    local L = rangeHeader()
    for i = 1, #r.rows do L[#L + 1] = r.rows[i] end
    if r.capped then L[#L + 1] = "  (row cap reached; later changes not recorded)" end
    local text = table.concat(L, "\n")
    if Nock.UI and Nock.UI.ShowCopyBox then Nock.UI.ShowCopyBox(text) else Nock:Print(text) end
    return
  end
  local T = _G.C_Timer
  if not (T and T.NewTicker) then Nock:Print("No ticker on this client."); return end
  r = { t0 = GetTime(), rows = {}, last = nil, cur = {} }
  self._range = r
  r.ticker = T.NewTicker(0.1, function()
    local cur = r.cur
    local okr, live = pcall(self.RangeReadings, self, cur)
    local line
    if not okr then line = "probe error: " .. tostring(live)
    elseif not live then line = "no live hostile target"
    else line = table.concat(cur, " ") end
    local inCombat = Nock.Flavor.Plain(_G.InCombatLockdown and InCombatLockdown()) == true
    local key = (inCombat and "C " or "  ") .. line
    if key == r.last then return end
    r.last = key
    if #r.rows >= RANGE_MAX_ROWS then r.capped = true; return end
    r.rows[#r.rows + 1] = ("  %7.2f  %s"):format(GetTime() - r.t0, key)
  end)
  Nock:Print("Range probe running. Walk slowly from melee straight out past 41 yd and back; /nock probe range mark <note> to mark a spot, /nock probe range again to stop and open the log.")
end

-- The Range Finder font preview (2026-09-24): one numbered row per font,
-- each with two real ladders in that font (compact with 25-28 lit, detailed
-- with the dead zone lit), so the label face can be picked by eye.
-- Candidates: Nock's bundled faces, the client's own, then every font other
-- addons registered with LibSharedMedia. `/nock probe fonts [size]` toggles.
-- Throwaway evidence tooling.
local FONT_ROWS_MAX = 24
local FONT_CANDIDATES = {
  { "Saira Extra Condensed Medium", [[Interface\AddOns\Nock\Media\SairaExtraCondensed-Medium.ttf]] },
  { "Saira Extra Condensed Bold",             [[Interface\AddOns\Nock\Media\SairaExtraCondensed-Bold.ttf]] },
  { "IBM Plex Sans Regular",                  [[Interface\AddOns\Nock\Media\IBMPlexSans-Regular.ttf]] },
  { "IBM Plex Sans Medium",                   [[Interface\AddOns\Nock\Media\IBMPlexSans-Medium.ttf]] },
  { "IBM Plex Sans SemiBold",                 [[Interface\AddOns\Nock\Media\IBMPlexSans-SemiBold.ttf]] },
  { "IBM Plex Mono Regular",                  [[Interface\AddOns\Nock\Media\IBMPlexMono-Regular.ttf]] },
  { "IBM Plex Mono Medium (current)",         [[Interface\AddOns\Nock\Media\IBMPlexMono-Medium.ttf]] },
  { "Lemon Milk Regular",                     [[Interface\AddOns\Nock\Media\LemonMilk-Regular.otf]] },
  { "Arial Narrow (client)",                  [[Fonts\ARIALN.TTF]] },
  { "Friz Quadrata (client)",                 [[Fonts\FRIZQT__.TTF]] },
}

function Probe:FontPreview(rest)
  if self._fontPreview then
    self._fontPreview:Hide()
    self._fontPreview = nil
    Nock:Print("Font preview closed.")
    return
  end
  local size = tonumber((rest or ""):match("%d+")) or 10
  local list, seen = {}, {}
  for _, c in ipairs(FONT_CANDIDATES) do list[#list + 1] = c; seen[c[2]:lower()] = true end
  local LSM = LibStub("LibSharedMedia-3.0", true)
  if LSM and LSM.HashTable then
    local names = {}
    for name, path in pairs(LSM:HashTable("font")) do
      if type(path) == "string" and not seen[path:lower()] then names[#names + 1] = name; seen[path:lower()] = true end
    end
    table.sort(names)
    local ht = LSM:HashTable("font")
    for _, name in ipairs(names) do list[#list + 1] = { name .. " (LSM)", ht[name] } end
  end
  local RL, L = Nock.UI.RangeLadder, Nock.RangeLadder
  local W, ROW_H, BAR_H = 220, 22, 14
  local rows = math.min(#list, FONT_ROWS_MAX)
  local f = CreateFrame("Frame", "NockFontPreview", UIParent, "BackdropTemplate")
  f:SetFrameStrata("DIALOG")
  f:SetSize(250 + 2 * (W + 12), 34 + rows * ROW_H)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  Nock.UI.ApplyBackdrop(f, { 0.05, 0.05, 0.06, 0.95 }, { 0, 0, 0, 1 })
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -8)
  title:SetText(("Range Finder label fonts at %d pt. Tell Claude the row number. /nock probe fonts [size] closes."):format(size))
  local dev = Nock.UI.PixelScale(f)
  local e = Nock.UI.DeviceWidth(1, dev)
  local compact, detailed = L.Layout(8, 35, true), L.Layout(8, 35, false)
  for i = 1, rows do
    local c = list[i]
    local y = -(28 + (i - 1) * ROW_H)
    local name = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    name:SetPoint("TOPLEFT", f, "TOPLEFT", 10, y - 3)
    name:SetText(("%d. %s"):format(i, c[1]))
    local opts = { bg = { 0.08, 0.08, 0.08, 0.9 }, border = { 0, 0, 0, 1 }, face = c[2], size = size }
    for j, spec in ipairs({ { compact, "25_28" }, { detailed, "DEAD" } }) do
      local okc, lad = pcall(RL.Create, f, opts)
      if okc and lad then
        lad:SetSize(W, BAR_H)
        lad:SetPoint("TOPLEFT", f, "TOPLEFT", 250 + (j - 1) * (W + 12), y)
        RL.Layout(lad, spec[1], W, BAR_H, true, dev, e)
        RL.Paint(lad, spec[2], true)
        lad:Show()
      end
    end
  end
  if #list > rows then
    Nock:Print(("Font preview: showing %d of %d fonts."):format(rows, #list))
  end
  f:Show()
  self._fontPreview = f
end

function Probe:Show(which, rest)
  local text
  if which == "range" then self:RangeRecord(rest); return end
  if which == "fonts" then self:FontPreview(rest); return end
  if which == "spells" then text = self:SpellbookReport()
  elseif which == "frames" then text = self:FramesReport()
  elseif which == "container" then
    text = self:ContainerSpike()
  elseif which == "aura" then
    local name, id = (rest or ""):match("^(.-)%s*(%d*)$")
    if name == "" then name = "Quick Shots" end
    self:WatchAura(name, tonumber(id) or 6150)
    return
  else text = self:Report() end
  if Nock.UI and Nock.UI.ShowCopyBox then Nock.UI.ShowCopyBox(text) else Nock:Print(text) end
end
