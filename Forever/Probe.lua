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
  if event == "UNIT_SPELLCAST_SUCCEEDED" and self._sting then self:OnStingCast(spellID) end
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
Probe.RestrictionRows = restrictionRows

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

-- The sting spike (feature request 2026-09-30: sting timers in the cooldown
-- grid, for the current target). Target auras are secret in combat, so the
-- question is whether the client will draw them for us: a one-button aura
-- container on `target`, own harmful auras only, filtered to the sting
-- ranks, sitting on top of a Nock-owned tile the way it would sit on a grid
-- slot. An unfiltered row under it is the control (does the client show ANY
-- own debuff of the target). The report also says what the aura API itself
-- answers for the target. Throwaway until proven.
-- Vanilla rank ids per sting (no Wyvern Sting on Forever); each is kept only
-- while the client gives it the family's name.
local STING_FAMILIES = {
  { key = "Serpent", ids = { 1978, 13549, 13550, 13551, 13552, 13553, 13554, 13555, 25295 } },
  { key = "Scorpid", ids = { 3043, 14275, 14276, 14277 } },
  { key = "Viper",   ids = { 3034, 14279, 14280 } },
}
local STING_W, STING_H, STING_CONTROL = 44, 32, 28

-- Pure: per family, the ids the client names like the family's first rank,
-- plus the spellbook's own id for that name (`book`: name -> id).
function Probe.StingIds(nameOf, book)
  local out = {}
  for _, fam in ipairs(STING_FAMILIES) do
    local name = nameOf(fam.ids[1])
    local row = { key = fam.key, name = name, ids = {}, dropped = 0 }
    local seen = {}
    for _, id in ipairs(fam.ids) do
      if name and nameOf(id) == name then
        row.ids[#row.ids + 1] = id
        seen[id] = true
      else
        row.dropped = row.dropped + 1
      end
    end
    local bookId = name and book and book[name]
    if type(bookId) == "number" then
      row.book = bookId
      if not seen[bookId] then row.ids[#row.ids + 1] = bookId end
    end
    out[#out + 1] = row
  end
  return out
end

-- One button in a grid tile's shape: black edge, dark ground, cropped icon,
-- the client's swipe and its countdown on a layer above the swipe. Each
-- hand-over is logged: the hook runs when the client first needs the button.
local function styleStingButton(b, w, h, log)
  if b._nockStyled then return end
  b._nockStyled = true
  local function step(name, fn)
    local okc, err = pcall(fn)
    log[#log + 1] = ("  button %s: %s"):format(name, okc and "ok" or ("err " .. tostring(err)))
    return okc
  end
  b:SetSize(w, h)
  local edge = b:CreateTexture(nil, "BACKGROUND", nil, -1)
  edge:SetAllPoints(b)
  edge:SetColorTexture(0, 0, 0, 1)
  local ground = b:CreateTexture(nil, "BACKGROUND")
  ground:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
  ground:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
  ground:SetColorTexture(0.08, 0.08, 0.08, 1)
  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
  icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
  if not (Nock.UI and Nock.UI.IconCoords and pcall(function() icon:SetTexCoord(Nock.UI.IconCoords(w, h)) end)) then
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  end
  step("SetIcon", function() b:SetIcon(icon) end)
  local cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
  cd:SetAllPoints(b)
  cd.noCooldownCount = true
  if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
  step("SetDurationCooldown", function() b:SetDurationCooldown(cd) end)
  local layer = CreateFrame("Frame", nil, b)
  layer:SetAllPoints(b)
  layer:SetFrameLevel(cd:GetFrameLevel() + 1)
  local time = layer:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  time:SetAllPoints(layer)
  time:SetJustifyH("CENTER")
  time:SetJustifyV("MIDDLE")
  local AR = Nock.ForeverAuraRow
  local fmt = AR and AR.DurationFormat and AR.DurationFormat()
  if not (fmt and step("SetDurationText (bare seconds)", function() b:SetDurationText(time, fmt) end)) then
    step("SetDurationText", function() b:SetDurationText(time) end)
  end
end

-- One field of a possibly-secret aura record, never compared.
local function auraField(a, k)
  local okc, v = pcall(function() return a[k] end)
  return okc and describe(v) or "err"
end

-- What the API itself says about the target, appended to L (every read
-- guarded).
local function stingReadings(L, fams)
  local inCombat = (InCombatLockdown and InCombatLockdown()) and true or false
  local rr = {}
  for _, r in ipairs(Probe.RestrictionRows()) do rr[#rr + 1] = r[1] .. "=" .. r[2] end
  L[#L + 1] = ("  in combat: %s  restrictions: %s"):format(tostring(inCombat), #rr > 0 and table.concat(rr, " ") or "n/a")
  local function read(fn, ...)
    if type(fn) ~= "function" then return "missing" end
    local okc, v = pcall(fn, ...)
    return okc and describe(v) or "err"
  end
  L[#L + 1] = ("  target: exists %s  guid %s  dead %s"):format(
    read(_G.UnitExists, "target"), read(_G.UnitGUID, "target"), read(_G.UnitIsDead, "target"))
  local UA = _G.C_UnitAuras
  if UA and UA.GetUnitAuraInstanceIDs then
    local okc, ids = pcall(UA.GetUnitAuraInstanceIDs, "target", "HARMFUL|PLAYER")
    local okn, n = pcall(function() return #ids end)
    if not okc then
      L[#L + 1] = "  GetUnitAuraInstanceIDs: err " .. tostring(ids)
    elseif not okn then
      L[#L + 1] = "  GetUnitAuraInstanceIDs: " .. describe(ids) .. " (no length)"
    else
      L[#L + 1] = ("  GetUnitAuraInstanceIDs(target, HARMFUL|PLAYER): %d"):format(n)
      for i = 1, math.min(n, 6) do
        local id = ids[i]
        local oka, a = pcall(UA.GetAuraDataByAuraInstanceID, "target", id)
        local okd, d = pcall(UA.GetAuraDuration, "target", id)
        L[#L + 1] = ("    #%d instance %s | data %s: spellId %s name %s duration %s expires %s source %s | GetAuraDuration %s"):format(
          i, describe(id), oka and type(a) or "err",
          auraField(a, "spellId"), auraField(a, "name"), auraField(a, "duration"),
          auraField(a, "expirationTime"), auraField(a, "sourceUnit"),
          okd and type(d) or ("err " .. tostring(d)))
      end
    end
  else
    L[#L + 1] = "  GetUnitAuraInstanceIDs: missing"
  end
  if UA and UA.GetAuraDataBySpellName then
    for _, f in ipairs(fams) do
      if f.name then
        local okc, a = pcall(UA.GetAuraDataBySpellName, "target", f.name, "HARMFUL|PLAYER")
        if not okc then
          L[#L + 1] = ("  GetAuraDataBySpellName(%s): err %s"):format(f.name, tostring(a))
        elseif a == nil then
          L[#L + 1] = ("  GetAuraDataBySpellName(%s): nil"):format(f.name)
        else
          L[#L + 1] = ("  GetAuraDataBySpellName(%s): %s spellId %s duration %s expires %s"):format(f.name,
            describe(a), auraField(a, "spellId"), auraField(a, "duration"), auraField(a, "expirationTime"))
        end
      end
    end
  end
end

-- Blizzard's own target frame re-reads its container on every target change
-- (TargetFrameMixin:OnEvent -> UpdateAllAuras): the container follows the
-- unit's aura events, not the token moving to another unit. Without this the
-- tiles kept a dead mob's countdown and lost a second target's sting
-- (user, 2026-09-30). `/nock probe sting refresh` flips it, to compare.
function Probe:OnStingTarget()
  local st = self._sting
  if not st or st.refreshOff then return end
  local r = st.refresh
  local inCombat = (InCombatLockdown and InCombatLockdown()) and true or false
  r.n = r.n + 1
  if inCombat then r.inCombat = r.inCombat + 1 end
  for _, c in ipairs({ st.sting, st.control }) do
    local okc, err = pcall(c.UpdateAllAuras, c)
    if not okc then
      r.err = r.err + 1
      r.lastErr = tostring(err) .. (inCombat and " (in combat)" or "")
    end
  end
end

-- Half a second after an own sting lands, the API readings are taken for the
-- next report: nobody opens a copybox mid-fight.
local STING_SNAPS = 4
function Probe:OnStingCast(spellID)
  local st = self._sting
  local n = Nock.Flavor.Plain(Nock.API.SpellName(spellID))
  if not (st and type(n) == "string" and st.names[n]) then return end
  local T = _G.C_Timer
  if not (T and T.After) then return end
  T.After(0.5, function()
    local L = {}
    L.at = GetTime()
    L.label = ("0.5 s after %s (%s)"):format(n, tostring(spellID))
    stingReadings(L, st.fams)
    st.snaps[#st.snaps + 1] = L
    if #st.snaps > STING_SNAPS then table.remove(st.snaps, 1) end
  end)
end

function Probe:StingSpike(rest)
  local st = self._sting
  if rest == "off" then
    if st then
      pcall(function() st.slot:Hide(); st.control:Hide() end)
    end
    return "sting probe: hidden (`/nock probe sting` shows it again)"
  end
  if rest == "refresh" and st then
    st.refreshOff = not st.refreshOff or nil
  end
  local L = {}
  local function step(name, fn)
    local okc, err = pcall(fn)
    L[#L + 1] = ("  %s: %s"):format(name, okc and "ok" or ("err " .. tostring(err)))
    return okc
  end
  local inCombat = (InCombatLockdown and InCombatLockdown()) and true or false
  local nameOf = function(id)
    local n = Nock.Flavor.Plain(Nock.API.SpellName(id))
    return type(n) == "string" and n or nil
  end
  local fams = Probe.StingIds(nameOf, Nock.ForeverSpellbookNames and Nock.ForeverSpellbookNames() or nil)
  local all = {}
  L[#L + 1] = "sting ids (kept = the client names them like rank 1):"
  for _, f in ipairs(fams) do
    for _, id in ipairs(f.ids) do all[#all + 1] = id end
    L[#L + 1] = ("  %s (%s): %s | spellbook %s | dropped %d"):format(f.key, tostring(f.name),
      #f.ids > 0 and table.concat(f.ids, " ") or "none", tostring(f.book), f.dropped)
  end

  if not st then
    L[#L + 1] = ("containers (new, built %s):"):format(inCombat and "IN COMBAT" or "out of combat")
    st = { log = {}, snaps = {}, names = {}, refresh = { n = 0, inCombat = 0, err = 0 } }
    local AU = _G.AnchorUtil or {}
    local axis, dir = AU.FlowLayoutAxis or {}, AU.FlowDirection or {}
    local AR = Nock.ForeverAuraRow
    local set = AR and AR.IdTable and AR.IdTable(all) or {}
    -- the stand-in for a grid slot: Nock's own frame, the idle sting icon on it
    if not step("slot", function()
      local slot = CreateFrame("Frame", "NockProbeStingSlot", UIParent)
      slot:SetSize(STING_W, STING_H)
      slot:SetPoint("CENTER", UIParent, "CENTER", 0, -220)
      slot:SetFrameStrata("HIGH")
      local bg = slot:CreateTexture(nil, "BACKGROUND")
      bg:SetAllPoints(slot)
      bg:SetColorTexture(0, 0, 0, 1)
      local idle = slot:CreateTexture(nil, "ARTWORK")
      idle:SetPoint("TOPLEFT", slot, "TOPLEFT", 1, -1)
      idle:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -1, 1)
      idle:SetTexture(Nock.API.SpellIcon(STING_FAMILIES[1].ids[1]))
      idle:SetTexCoord(0.08, 0.92, 0.2, 0.8)
      st.slot = slot
    end) then return table.concat(L, "\n") end
    local function build(label, name, parent, anchor, group, w, h, maxFrames, filters)
      local c
      if not step(label .. " CreateFrame", function()
        c = CreateFrame("AuraContainer", name, parent, "CustomAuraContainerTemplate")
      end) then return nil end
      step(label .. " anchor", function() anchor(c) end)
      step(label .. " SetUnit(target)", function() c:SetUnit("target") end)
      step(label .. " flow layout", function()
        c:SetFlowLayoutAxis(axis.Horizontal or 0)
        c:SetFlowLayoutGrowthDirection(dir.Right or 1, dir.Down or -1)
        c:SetFlowLayoutAnchorPoint("TOPLEFT")
      end)
      step(label .. " AddAuraGroup(HARMFUL|PLAYER)", function()
        c:AddAuraGroup(group, "HARMFUL|PLAYER", {
          maxFrameCount = maxFrames,
          candidateFilters = filters,
          initializeFrame = function(b) styleStingButton(b, w, h, st.log) end,
          layout = { elementWidth = w, elementHeight = h, elementSpacing = 2 },
        })
      end)
      step(label .. " enable + show", function() c:SetEnabled(true); c:Show() end)
      return c
    end
    -- on the slot: the filtered, one-tile container (what the feature would be)
    st.sting = build("sting", "NockProbeStingContainer", st.slot, function(c)
      c:SetPoint("TOPLEFT", st.slot, "TOPLEFT", 0, 0)
      c:SetFrameLevel(st.slot:GetFrameLevel() + 5)
    end, "sting", STING_W, STING_H, 1, { includeSpellIDs = set })
    -- under it: every own debuff of the target, unfiltered (the control)
    st.control = build("control", "NockProbeStingControl", UIParent, function(c)
      c:SetPoint("TOPLEFT", st.slot, "BOTTOMLEFT", 0, -10)
      c:SetFrameStrata("HIGH")
    end, "own", STING_CONTROL, STING_CONTROL, 6, nil)
    self._sting = st
    step("PLAYER_TARGET_CHANGED", function() self:RegisterEvent("PLAYER_TARGET_CHANGED", "OnStingTarget") end)
  else
    L[#L + 1] = "containers (existing):"
    pcall(function() st.slot:Show(); if st.control then st.control:Show() end end)
  end
  st.fams = fams
  for _, f in ipairs(fams) do if f.name then st.names[f.name] = true end end
  if st.sting then step("sting UpdateAllAuras", function() st.sting:UpdateAllAuras() end) end
  if st.control then step("control UpdateAllAuras", function() st.control:UpdateAllAuras() end) end
  -- three hand-overs per button; only a refused one is worth a line
  local handed, refused = 0, 0
  for i = 1, #st.log do
    if st.log[i]:find(": ok", 1, true) then handed = handed + 1 else refused = refused + 1; L[#L + 1] = st.log[i] end
  end
  L[#L + 1] = ("buttons built: %d (hand-overs ok %d, refused %d)"):format(math.floor(#st.log / 3 + 0.5), handed, refused)
  local r = st.refresh
  L[#L + 1] = ("re-read on target change: %s | changes %d (in combat %d) | refused %d%s"):format(
    st.refreshOff and "OFF" or "on", r.n, r.inCombat, r.err, r.lastErr and (" | last: " .. r.lastErr) or "")

  L[#L + 1] = "readings now:"
  stingReadings(L, fams)
  local now = GetTime()
  for i = 1, #st.snaps do
    local s = st.snaps[i]
    L[#L + 1] = ("readings %.0f s ago, %s:"):format(now - s.at, s.label)
    for j = 1, #s do L[#L + 1] = s[j] end
  end
  if #st.snaps == 0 then L[#L + 1] = "no sting cast seen yet (the readings after a cast are kept for this report)" end
  L[#L + 1] = "look below the screen centre: a wide sting tile (the idle icon), and a row under it for every own debuff of the target."
  L[#L + 1] = "`/nock probe sting refresh` flips the re-read on target change; `/nock probe sting off` hides both."
  return table.concat(L, "\n")
end

-- The range-ladder probe (Range Finder ladder, 2026-09-24): which range
-- checks answer on Forever, whether they stay plain in combat, and in which
-- order they flip as the hunter walks away from a target. Records a row every
-- time any reading changes, until stopped. TBC's ladder items first (yards
-- from the reference WA), then other LibRangeCheck candidates, the four
-- interact distances, and the hunter's spells. Throwaway evidence tooling.
local RANGE_ITEMS = {
  { 15826, "~5 salve" }, { 8149, "~5 melee" }, { 34368, "~8" }, { 9606, "~10 vessel" }, { 32321, "~10" },
  { 4559, "~15 chu" }, { 33069, "~15" }, { 1191, "~20 marbles" }, { 10645, "~20" }, { 24268, "~25" },
  { 13289, "~25" }, { 835, "~30" }, { 7734, "~30" }, { 18904, "~35" }, { 4945, "~40" }, { 28767, "~40" },
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
  -- IsItemInRange answers only for items the client has loaded: a probe item
  -- nobody carries reads "-" from a cold cache until it is requested.
  local CI = _G.C_Item
  if CI and CI.RequestLoadItemDataByID then
    for _, it in ipairs(RANGE_ITEMS) do pcall(CI.RequestLoadItemDataByID, it[1]) end
  end
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

-- Movement-key spike (2026-09-29): does IsKeyDown answer in combat, and
-- does W+S count as moving? The weave glide has no velocity on Forever
-- (GetUnitSpeed secret); the bound movement keys would give it radial
-- intent without rerouting anything. Throwaway evidence tooling.
local KEY_ACTIONS = {
  "MOVEFORWARD", "MOVEBACKWARD", "STRAFELEFT", "STRAFERIGHT", "TURNLEFT", "TURNRIGHT",
  "MOVEANDSTEER", "TOGGLEAUTORUN",
}
local KEY_MOUSE = { "LeftButton", "RightButton" }
local KEYS_MAX_ROWS = 600

-- Pure: the column list, one per bound key of each action plus the mouse
-- buttons. `bindingKey(action)` returns the bound keys (GetBindingKey).
function Probe.KeysColumns(bindingKey)
  local cols = {}
  for _, action in ipairs(KEY_ACTIONS) do
    local k1, k2 = bindingKey(action)
    if k1 then cols[#cols + 1] = { key = k1, action = action } end
    if k2 then cols[#cols + 1] = { key = k2, action = action } end
    if not k1 and not k2 then cols[#cols + 1] = { key = nil, action = action } end
  end
  for _, b in ipairs(KEY_MOUSE) do cols[#cols + 1] = { key = b, action = "mouse" } end
  return cols
end

function Probe:KeysReadings(cols, out)
  local IKD, IMBD = _G.IsKeyDown, _G.IsMouseButtonDown
  local n = 0
  for _, c in ipairs(cols) do
    n = n + 1
    if not c.key then out[n] = "-"
    elseif IKD then out[n] = rangeToken(pcall(IKD, c.key))
    else out[n] = "E" end
  end
  -- the same forward key with excludeBindingState = true (meaning unknown)
  local fwd = cols[1] and cols[1].key
  n = n + 1
  if fwd and IKD then out[n] = rangeToken(pcall(IKD, fwd, true)) else out[n] = "-" end
  for _, b in ipairs(KEY_MOUSE) do
    n = n + 1
    if IMBD then out[n] = rangeToken(pcall(IMBD, b)) else out[n] = "E" end
  end
  n = n + 1
  if _G.IsPlayerMoving then out[n] = rangeToken(pcall(_G.IsPlayerMoving)) else out[n] = "E" end
  n = n + 1
  local okf, f = pcall(_G.GetPlayerFacing or function() return nil end)
  f = okf and Nock.Flavor.Plain(f) or nil
  out[n] = type(f) == "number" and ("%.2f"):format(f) or rangeToken(okf, f)
  for i = n + 1, #out do out[i] = nil end
end

local function keysHeader(cols)
  local L = {}
  L[#L + 1] = "Nock probe keys  (T down, F up, - unbound/no answer, S secret, E error)"
  L[#L + 1] = "columns:"
  local c = 0
  for _, col in ipairs(cols) do c = c + 1; L[#L + 1] = ("  %2d %s  IsKeyDown(%s)"):format(c, col.action, tostring(col.key)) end
  c = c + 1; L[#L + 1] = ("  %2d MOVEFORWARD key with excludeBindingState = true"):format(c)
  for _, b in ipairs(KEY_MOUSE) do c = c + 1; L[#L + 1] = ("  %2d IsMouseButtonDown(%s)"):format(c, b) end
  c = c + 1; L[#L + 1] = ("  %2d IsPlayerMoving"):format(c)
  c = c + 1; L[#L + 1] = ("  %2d GetPlayerFacing"):format(c)
  L[#L + 1] = "rows (seconds since start, C = in combat, then columns 1..n; a row only when something changed; MOVE lines = PLAYER_STARTED/STOPPED_MOVING):"
  return L
end

function Probe:KeysRecord(rest)
  local r = self._keys
  if r then
    r.ticker:Cancel()
    self:UnregisterEvent("PLAYER_STARTED_MOVING")
    self:UnregisterEvent("PLAYER_STOPPED_MOVING")
    self._keys = nil
    local L = keysHeader(r.cols)
    for i = 1, #r.rows do L[#L + 1] = r.rows[i] end
    if r.capped then L[#L + 1] = "  (row cap reached; later changes not recorded)" end
    local text = table.concat(L, "\n")
    if Nock.UI and Nock.UI.ShowCopyBox then Nock.UI.ShowCopyBox(text) else Nock:Print(text) end
    return
  end
  local T = _G.C_Timer
  if not (T and T.NewTicker) then Nock:Print("No ticker on this client."); return end
  local GBK = _G.GetBindingKey or function() return nil end
  r = { t0 = GetTime(), rows = {}, last = nil, cur = {}, cols = Probe.KeysColumns(GBK) }
  self._keys = r
  local function mark(text)
    if #r.rows >= KEYS_MAX_ROWS then r.capped = true; return end
    r.rows[#r.rows + 1] = ("  %7.2f  %s"):format(GetTime() - r.t0, text)
  end
  self:RegisterEvent("PLAYER_STARTED_MOVING", function() mark("MOVE started") end)
  self:RegisterEvent("PLAYER_STOPPED_MOVING", function() mark("MOVE stopped") end)
  r.ticker = T.NewTicker(0.05, function()
    local cur = r.cur
    local okr, err = pcall(self.KeysReadings, self, r.cols, cur)
    local line = okr and table.concat(cur, " ") or ("probe error: " .. tostring(err))
    local inCombat = Nock.Flavor.Plain(_G.InCombatLockdown and InCombatLockdown()) == true
    local key = (inCombat and "C " or "  ") .. line
    if key == r.last then return end
    r.last = key
    mark(key)
  end)
  Nock:Print("Keys probe running. Out of combat then in combat: W, S, W+S together, a strafe, a turn, both mouse buttons; /nock probe keys again to stop and open the log.")
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
  title:SetText(("Range Finder label fonts at %d pt. Note the row number. /nock probe fonts [size] closes."):format(size))
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

-- The talent dump: spec index 0..3 (0 = omitted), tier 1..12, column 1..4.
-- The first error per index is kept (the query's rules show in it). Pure
-- over `getInfo` so it tests without a client.
function Probe.TalentReport(getInfo)
  local L = {}
  if type(getInfo) ~= "function" then return "C_SpecializationInfo.GetTalentInfo: missing" end
  local total = 0
  for spec = 0, 3 do
    local n, firstErr = 0, nil
    for tier = 1, 12 do
      for col = 1, 4 do
        local q = { tier = tier, column = col }
        if spec > 0 then q.specializationIndex = spec end
        local okc, r = pcall(getInfo, q)
        if not okc then
          firstErr = firstErr or tostring(r)
        elseif type(r) == "table" and type(r.name) == "string" and r.name ~= "" then
          n = n + 1
          L[#L + 1] = ("spec %d  tier %d  col %d  %s  spell %s  talent %s  rank %s/%s"):format(
            spec, tier, col, r.name, tostring(r.spellID), tostring(r.talentID), tostring(r.rank), tostring(r.maxRank))
        end
      end
    end
    total = total + n
    L[#L + 1] = ("-- spec index %d: %d talents%s"):format(spec, n, firstErr and ("  (first error: " .. firstErr .. ")") or "")
  end
  L[#L + 1] = ("talents found: %d"):format(total)
  return table.concat(L, "\n")
end

-- `/nock probe tracking` (Forever/Tracking.lua): the minimap tracking list
-- with the active flag, the target's creature type against the client's
-- type names and the Track spell it wants, the talent rows whose name has
-- "Track" (to pin Improved Tracking's id) and the published state. Pure
-- over `d` = { list, creatureType, typeNames, rank, improvedId, talents, state }.
function Probe.TrackingReport(d)
  local L = { "Nock probe tracking" }
  if type(d.list) ~= "table" then
    L[#L + 1] = "no tracking list (C_Minimap.GetTrackingInfo missing or secret)"
  else
    L[#L + 1] = ("-- tracking list: %d entries"):format(#d.list)
    for i, e in ipairs(d.list) do
      L[#L + 1] = ("%2d  %-4s  spell %-6s  %s"):format(i, e.active and "ON" or "off", tostring(e.spellID), tostring(e.name))
    end
  end
  L[#L + 1] = ("creature type: %s"):format(tostring(d.creatureType))
  -- The raw target reads (name = value), so a secret or an error shows as such.
  if type(d.raw) == "table" then
    local parts = {}
    for _, r in ipairs(d.raw) do parts[#parts + 1] = r[1] .. "=" .. tostring(r[2]) end
    L[#L + 1] = "raw target: " .. table.concat(parts, "  ")
  end
  if type(d.typeNames) == "table" then
    local ids = {}
    for id in pairs(d.typeNames) do ids[#ids + 1] = id end
    table.sort(ids)
    local parts = {}
    for _, id in ipairs(ids) do parts[#parts + 1] = ("%d = %s"):format(id, tostring(d.typeNames[id])) end
    L[#L + 1] = "client type names: " .. table.concat(parts, ", ")
  else
    L[#L + 1] = "client type names: none (English fallback)"
  end
  local need = Nock.TrackingForCreatureType and Nock.TrackingForCreatureType(d.creatureType, d.typeNames)
  L[#L + 1] = ("wants %s"):format(tostring(need))
  L[#L + 1] = ("Improved Tracking: id %s  rank %s"):format(tostring(d.improvedId), tostring(d.rank))
  for _, t in ipairs(d.talents or {}) do
    L[#L + 1] = ("talent  %s  spell %s  rank %s"):format(tostring(t.name), tostring(t.spellID), tostring(t.rank))
  end
  local st = d.state
  if st then
    local known = {}
    for id in pairs(st.known or {}) do known[#known + 1] = tostring(id) end
    table.sort(known)
    L[#L + 1] = ("state: activeId %s  targetTrackId %s  wrong %s  known %s"):format(
      tostring(st.activeId), tostring(st.targetTrackId), tostring(st.wrong), table.concat(known, ","))
  end
  return table.concat(L, "\n")
end

-- The retail-style talent tree (C_ClassTalents + C_Traits): the active
-- loadout's trees, or the spec's tree through the view-only loadout when no
-- loadout exists yet. One line per node entry: spell id, name, rank.
-- `api` = { CT = C_ClassTalents, T = C_Traits, SI = C_SpecializationInfo,
-- name = fn(spellID), viewID = Constants.TraitConsts.VIEW_TRAIT_CONFIG_ID }.
function Probe.TraitReport(api)
  local L = {}
  local CT, T, SI = api.CT, api.T, api.SI
  if not (T and T.GetTreeNodes and T.GetNodeInfo) then return "C_Traits: missing" end
  local function call(f, ...)
    if type(f) ~= "function" then return nil, "missing" end
    local okc, a, b = pcall(f, ...)
    if not okc then return nil, tostring(a) end
    return a, b
  end
  local specIndex = SI and call(SI.GetSpecialization)
  local specID = specIndex and SI and call(SI.GetSpecializationInfo, specIndex)
  L[#L + 1] = ("spec index %s  spec id %s"):format(tostring(specIndex), tostring(specID))
  local configID, why = CT and call(CT.GetActiveConfigID)
  L[#L + 1] = ("active config: %s%s"):format(tostring(configID), why and ("  (" .. why .. ")") or "")
  local trees = {}
  if configID then
    local info = call(T.GetConfigInfo, configID)
    for _, t in ipairs(type(info) == "table" and info.treeIDs or {}) do trees[#trees + 1] = t end
  end
  if #trees == 0 and specID and CT then
    local tree, terr = call(CT.GetTraitTreeForSpec, specID)
    L[#L + 1] = ("tree for spec %s: %s%s"):format(tostring(specID), tostring(tree), terr and ("  (" .. terr .. ")") or "")
    if tree then
      trees[1] = tree
      if not configID and api.viewID then
        local _, verr = call(CT.InitializeViewLoadout, specID, 100)
        configID = api.viewID
        L[#L + 1] = ("view loadout: %s"):format(verr and ("error " .. verr) or "ok")
      end
    end
  end
  local n = 0
  for _, tree in ipairs(trees) do
    local nodes = call(T.GetTreeNodes, tree) or {}
    L[#L + 1] = ("-- tree %s: %d nodes"):format(tostring(tree), #nodes)
    for _, nodeID in ipairs(nodes) do
      local node = call(T.GetNodeInfo, configID, nodeID)
      if type(node) == "table" then
        for _, entryID in ipairs(node.entryIDs or {}) do
          local entry = call(T.GetEntryInfo, configID, entryID)
          local def = type(entry) == "table" and entry.definitionID and call(T.GetDefinitionInfo, entry.definitionID)
          local sid = type(def) == "table" and def.spellID or nil
          local nm = (type(def) == "table" and def.overrideName) or (sid and api.name and api.name(sid)) or "?"
          n = n + 1
          L[#L + 1] = ("node %s  entry %s  spell %s  %s  rank %s/%s"):format(tostring(nodeID), tostring(entryID),
            tostring(sid), tostring(nm), tostring(node.activeRank), tostring(node.maxRanks))
        end
      end
    end
  end
  L[#L + 1] = ("entries found: %d"):format(n)
  return table.concat(L, "\n")
end

-- Cooldown catalog discovery: every spell the character could put on the
-- grid -- the spellbook and the talent tree, taken or not -- with what the
-- client says about its cooldown, so the catalog can be built from the
-- client rather than typed from a wiki. `api` (all optional, injectable):
-- book() / talents() -> { {id, name, src, passive?, rank?, max?} },
-- passive(id), baseCd(id) -> ms, gcdMs, tipCd(id) -> text, curCd(id) -> s,
-- charges(id) -> max, key(id) -> tracked catalog key, level, inCombat.
function Probe.CdCatalogReport(api)
  local function fmt(v) if v == nil then return "-" end return tostring(v) end
  local L = { ("cooldown catalog probe  level %s%s"):format(fmt(api.level),
    api.inCombat and "  (IN COMBAT: values may be hidden, rerun out of combat)" or "") }
  L[#L + 1] = "src  spellID  name | passive | baseCd/gcd ms | tooltip cooldown | current cd | charges | tracked key"
  local seen, rows = {}, {}
  for _, e in ipairs(api.book and api.book() or {}) do
    if e.id and not seen[e.id] then seen[e.id] = e; rows[#rows + 1] = e end
  end
  for _, e in ipairs(api.talents and api.talents() or {}) do
    if e.id and seen[e.id] then
      seen[e.id].src = seen[e.id].src .. "+talent"
    elseif e.id then
      seen[e.id] = e; rows[#rows + 1] = e
    end
  end
  local actives, withCd = 0, 0
  for _, e in ipairs(rows) do
    local passive = e.passive
    if passive == nil and api.passive then passive = api.passive(e.id) end
    local base, gcd
    if api.baseCd then base, gcd = api.baseCd(e.id) end
    local tip = api.tipCd and api.tipCd(e.id)
    if not passive then
      actives = actives + 1
      if (type(base) == "number" and base > 0) or tip then withCd = withCd + 1 end
    end
    L[#L + 1] = ("%-12s %7s  %s%s | %s | %s/%s | %s | %s | %s | %s"):format(e.src, fmt(e.id), fmt(e.name),
      e.rank and (" [rank " .. fmt(e.rank) .. "/" .. fmt(e.max) .. "]") or "",
      passive and "PASSIVE" or "active", fmt(base), fmt(gcd), fmt(tip),
      fmt(api.curCd and api.curCd(e.id)), fmt(api.charges and api.charges(e.id)), fmt(api.key and api.key(e.id)))
  end
  L[#L + 1] = ("spells: %d  active: %d  active with a cooldown signal: %d"):format(#rows, actives, withCd)
  return table.concat(L, "\n")
end

-- The secure-snippet probe (in-game only: every step is the client's).
function Probe.SecureReport()
  local L = {}
  local function row(k, v) L[#L + 1] = ("%s: %s"):format(k, tostring(v)) end
  row("in combat", InCombatLockdown and InCombatLockdown() or false)
  row("loadstring_untainted", type(_G.loadstring_untainted))
  row("SecureHandlerExecute", type(_G.SecureHandlerExecute))
  row("SecureHandlerWrapScript", type(_G.SecureHandlerWrapScript))
  local h = Probe._secureH
  if not h and InCombatLockdown and InCombatLockdown() then
    -- a secure frame built under lockdown comes out unprotected and every
    -- snippet on it errors: the first run must be out of combat
    row("not built yet", "run /nock probe secure once OUT of combat first (after every /reload)")
    return table.concat(L, "\n")
  end
  if not h then
    local okc, f = pcall(CreateFrame, "Frame", "NockProbeSecureHandler", UIParent, "SecureHandlerBaseTemplate")
    row("handler frame", okc and "ok" or ("error " .. tostring(f)))
    if not okc then return table.concat(L, "\n") end
    h = f
    Probe._secureH = h
    -- GetMousePosition in a snippet is relative to the frame and nil while
    -- the cursor is off it: the handler covers the whole screen
    pcall(h.SetAllPoints, h, UIParent)
  end
  local okp, prot, explicit = pcall(h.IsProtected, h)
  row("handler protected (protected, explicit)", okp and (tostring(prot) .. ", " .. tostring(explicit)) or "n/a")
  -- 1. a plain Execute. The snippet bumps a counter the addon only READS
  --    (an insecure SetAttribute on a protected frame is blocked in combat,
  --    so nothing is reset; before/after tells whether it ran THIS time).
  local combat = InCombatLockdown and InCombatLockdown() or false
  local ranBefore = h:GetAttribute("nockRuns") or 0
  local oke, err = pcall(_G.SecureHandlerExecute, h, [[ self:SetAttribute("nockRuns", (self:GetAttribute("nockRuns") or 0) + 1) ]])
  row("Execute", oke and "no error" or ("error " .. tostring(err)))
  row("Execute ran this time", (h:GetAttribute("nockRuns") or 0) > ranBefore)
  -- 2. the cursor inside a snippet (what the ring's flick would read); the
  --    handler covers the screen, so this is the cursor's screen fraction
  local mBefore = h:GetAttribute("nockMouseRuns") or 0
  local okm, merr = pcall(_G.SecureHandlerExecute, h, [[
    local x, y = self:GetMousePosition()
    self:SetAttribute("nockMx", x and string.format("%.3f,%.3f", x, y) or "nil")
    self:SetAttribute("nockMouseRuns", (self:GetAttribute("nockMouseRuns") or 0) + 1)
  ]])
  if not okm then
    row("GetMousePosition in a snippet", "error " .. tostring(merr))
  else
    row("GetMousePosition in a snippet", ((h:GetAttribute("nockMouseRuns") or 0) > mBefore)
      and tostring(h:GetAttribute("nockMx")) or "did not run")
  end
  -- 3. a wrapped OnClick on a secure button: does the pre-snippet run and can
  --    it set the button's macrotext (the in-combat cast path)?
  local b = Probe._secureB
  if not b and not (InCombatLockdown and InCombatLockdown()) then
    local okb, bf = pcall(CreateFrame, "Button", "NockProbeSecureButton", UIParent, "SecureActionButtonTemplate")
    if okb then
      b = bf
      Probe._secureB = b
      -- a square to click with the MOUSE: wrapped handlers may only run on
      -- a hardware click, not on b:Click() from addon code
      b:SetSize(48, 48)
      b:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
      b:RegisterForClicks("AnyDown", "AnyUp")
      local t = b:CreateTexture(nil, "ARTWORK")
      t:SetAllPoints(b)
      t:SetColorTexture(0.9, 0.2, 0.9, 0.8)
      local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      fs:SetPoint("TOP", b, "BOTTOM", 0, -2)
      fs:SetText("click me, then /nock probe secure")
      local okw, werr = pcall(_G.SecureHandlerWrapScript, b, "OnClick", h, [[
        self:SetAttribute("nockClicked", (self:GetAttribute("nockClicked") or 0) + 1)
        self:SetAttribute("type", "macro")
        self:SetAttribute("macrotext", "")
      ]])
      row("WrapScript", okw and "ok" or ("error " .. tostring(werr)))
    else
      row("secure button", "error " .. tostring(bf))
    end
  end
  if b then
    if not combat then
      local before = b:GetAttribute("nockClicked") or 0
      pcall(b.Click, b)
      row("wrapped OnClick ran on b:Click()", (b:GetAttribute("nockClicked") or 0) > before)
    end
    row("clicks counted by the snippet (mouse on the pink square)", b:GetAttribute("nockClicked") or 0)
    row("macrotext set from the snippet", b:GetAttribute("type") == "macro")
  else
    row("wrapped OnClick", "button not built (run once out of combat first)")
  end
  return table.concat(L, "\n")
end

-- `/nock probe weave`: the weave helper's state and the four spec questions
-- (spec 2026-09-28 §6) answered from the helper's state, the swing samples
-- and the cast ring. Pure over `src`:
--   stage, legIn, legOut, learnedIn, learnedOut, moving, playerMovingPlain,
--   mhRangeEvents, raptorId, swings = { {t, swingType, duration} },
--   casts = { {t, ev, spellID} }
function Probe.WeaveReport(src)
  local L = {}
  local function row(s) L[#L + 1] = s end
  row(("stage: %s  moving: %s"):format(tostring(src.stage), tostring(src.moving)))
  row(("legIn %.2f (%s)  legOut %.2f (%s)  legOutBack %.2f (%s)"):format(src.legIn or 0, src.learnedIn and "learned" or "seed",
    src.legOut or 0, src.learnedOut and "learned" or "seed", src.legOutBack or 0, src.learnedOutBack and "learned" or "seed"))
  row(("radial %.2f  face %d  pos %.2f  shootFrac %.2f (%s)"):format(src.radial or 0, src.face or 1, src.pos or 0,
    src.shootFrac or 0, src.learnedFrac and "learned" or "seed"))
  row(("IsPlayerMoving plain in combat: %s"):format(tostring(src.playerMovingPlain)))
  row(("MainHand PLAYER_SWING_RANGE_UPDATE events: %d"):format(src.mhRangeEvents or 0))
  row("")
  -- The helper's own ring: how the engine classed each event as it arrived
  -- (a Ranged event = shot or the client's reset), and the stage it left.
  row("helper events (how the engine classed them):")
  for _, h in ipairs(src.helper or {}) do
    if h.kind == "Ranged" then
      row(("  %.2f  Ranged  %s  stage %s"):format(h.t, h.shot and "shot" or "reset", tostring(h.stage)))
    else
      row(("  %.2f  %s  stage %s  legIn %.2f"):format(h.t, tostring(h.kind), tostring(h.stage), h.legIn or 0))
    end
  end
  row("")
  -- Every stage change with what the decision saw: zone, the swing's age,
  -- seconds until the white swing and Raptor are ready, movement.
  row("stage transitions (what the decision saw):")
  for _, x in ipairs(src.transitions or {}) do
    row(("  %.2f  %s -> %s  zone %s  age %.2f  melee %.2f  raptor %.2f  moving %s  radial %.2f  lateral %.2f  face %d"):format(
      x.t, tostring(x.from), tostring(x.to), tostring(x.zone), x.age or 0, x.melee or 0, x.raptor or 0, tostring(x.moving),
      x.radial or 0, x.lateral or 0, x.face or 1))
  end
  row("")
  row("swing events (MainHand = 0, OffHand = 1, Ranged = 2):")
  local swings = src.swings or {}
  local RANGED, MH = 2, 0
  for i = 1, #swings do
    local s = swings[i]
    row(("  %.2f  kind %s  dur %.2f"):format(s.t, tostring(s.swingType), s.duration or 0))
    if s.swingType == MH then
      local seen = false
      for j = i + 1, #swings do
        local n = swings[j]
        if n.t - s.t > 0.1 then break end
        if n.swingType == RANGED then
          row(("    Ranged event %.3f s after a MainHand hit: client reset"):format(n.t - s.t))
          seen = true
          break
        end
      end
      if not seen then row(("    no Ranged event within 0.1 s of the hit at %.2f"):format(s.t)) end
      for _, c in ipairs(src.casts or {}) do
        if c.spellID == src.raptorId and c.ev == "UNIT_SPELLCAST_SUCCEEDED" and c.t <= s.t and s.t - c.t <= 2 then
          row(("    Raptor Strike SUCCEEDED %.2f s before the hit at %.2f"):format(s.t - c.t, s.t))
        end
      end
    end
  end
  return table.concat(L, "\n")
end

-- `/nock probe aspect`: which signals can tell, IN COMBAT, that an aspect
-- dropped without a cast (a right-click on the buff, a /cancelaura)? For 60 s
-- (or until `/nock probe aspect stop`) it samples every candidate at 4 Hz and
-- logs only the changes, plus every cancel route the client runs (the global
-- cancels, /cancelaura, the default buff buttons' clicks) with its arguments
-- described plain or secret. Hooks stay installed; they log only while armed.
local ASPECT_SECONDS = 60
local aw -- the armed session, or nil

local function awLog(fmt, ...)
  if not aw then return end
  aw.L[#aw.L + 1] = ("%7.2f  " .. fmt):format(GetTime() - aw.t0, ...)
end

local function awCall(fn, ...)
  if type(fn) ~= "function" then return "n/a" end
  local okc, v = pcall(fn, ...)
  if not okc then return "ERR" end
  if type(v) == "table" then return "table" end
  return describe(v)
end

-- Every learned aspect: the base id, the learned rank's id (by name) and the
-- action slots holding it. Built when armed (out of combat ideally).
local function awAspects()
  local list = {}
  local S, API = Nock.Spells, Nock.API
  for base in pairs(S.ASPECTS) do
    local name = Nock.Flavor.Plain(API.SpellName(base))
    local learned = type(name) == "string" and select(6, API.SpellInfo(name)) or nil
    learned = Nock.Flavor.Plain(learned)
    list[#list + 1] = { base = base, name = name or ("#" .. base), id = type(learned) == "number" and learned or base, slots = {} }
  end
  table.sort(list, function(a, b) return a.base < b.base end)
  if _G.GetActionInfo then
    for slot = 1, 180 do
      local okc, kind, id = pcall(GetActionInfo, slot)
      if okc and kind == "spell" and type(Nock.Flavor.Plain(id)) == "number" then
        for _, a in ipairs(list) do
          if id == a.id or id == a.base then a.slots[#a.slots + 1] = slot end
        end
      end
    end
  end
  return list
end

-- One sample: key -> described value, every candidate signal.
local function awSample(list, out)
  local CS, CU = _G.C_Spell, _G.C_UnitAuras
  out.aurasSecret = describe(Nock.AuraCache and Nock.AuraCache.AurasSecret and Nock.AuraCache.AurasSecret())
  out.inCombat = describe(InCombatLockdown and InCombatLockdown())
  local pa = Nock.state.player.aspect
  out.stateAspect = pa and tostring(pa.name) or "nil"
  out.stateTrueshot = describe(Nock.state.player.trueshot)
  out.shapeshiftForm = awCall(_G.GetShapeshiftForm)
  for _, a in ipairs(list) do
    local k = a.name
    out[k .. " IsCurrentSpell"] = awCall(_G.IsCurrentSpell, a.id)
    out[k .. " C_Spell.IsCurrentSpell"] = awCall(CS and CS.IsCurrentSpell, a.id)
    out[k .. " GetPlayerAuraBySpellID"] = awCall(CU and CU.GetPlayerAuraBySpellID, a.id)
    out[k .. " GetAuraDataBySpellName"] = awCall(CU and CU.GetAuraDataBySpellName, "player", a.name, "HELPFUL")
    for _, slot in ipairs(a.slots) do
      out[k .. " IsCurrentAction(" .. slot .. ")"] = awCall(_G.IsCurrentAction, slot)
    end
  end
end

local function awArgs(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[i] = describe((select(i, ...))) end
  return table.concat(parts, ", ")
end

local awHooked, awButtons = false, {}

-- The default buff buttons: classic BuffButtonN and the modern BuffFrame
-- pool. HookScript is a post-hook; it logs what the button can tell us.
local function awHookButtons()
  local function hook(b, label)
    if not b or awButtons[b] or not b.HookScript then return end
    awButtons[b] = true
    b:HookScript("OnClick", function(self, button)
      local icon = self.Icon or self.icon or (self.GetName and self:GetName() and _G[self:GetName() .. "Icon"])
      local info = self.buttonInfo
      awLog("CLICK %s %s  index=%s auraInstanceID=%s info.index=%s info.auraInstanceID=%s icon=%s",
        label, describe(button), describe(self.GetID and self:GetID()), describe(self.auraInstanceID),
        describe(type(info) == "table" and info.index), describe(type(info) == "table" and info.auraInstanceID),
        describe(icon and icon.GetTexture and icon:GetTexture()))
    end)
  end
  for i = 1, 40 do hook(_G["BuffButton" .. i], "BuffButton" .. i) end
  local bf = _G.BuffFrame
  if bf and type(bf.auraFrames) == "table" then
    for i, b in ipairs(bf.auraFrames) do hook(b, "auraFrames[" .. i .. "]") end
  end
  if bf and bf.AuraContainer and bf.AuraContainer.GetChildren then
    for i, b in ipairs({ bf.AuraContainer:GetChildren() }) do hook(b, "AuraContainer[" .. i .. "]") end
  end
end

local function awInstallHooks()
  if awHooked or not _G.hooksecurefunc then return end
  awHooked = true
  for _, fn in ipairs({ "CancelUnitBuff", "CancelSpellByName", "CancelPlayerBuff" }) do
    if _G[fn] then hooksecurefunc(fn, function(...) awLog("%s(%s)", fn, awArgs(...)) end) end
  end
  local CU = _G.C_UnitAuras
  if CU then
    for _, fn in ipairs({ "CancelAuraByAuraInstanceID", "CancelAuraBySpellID" }) do
      if CU[fn] then hooksecurefunc(CU, fn, function(...) awLog("C_UnitAuras.%s(%s)", fn, awArgs(...)) end) end
    end
  end
  local SC = _G.SecureCmdList
  if type(SC) == "table" and type(SC.CANCELAURA) == "function" then
    hooksecurefunc(SC, "CANCELAURA", function(msg) awLog("SecureCmdList.CANCELAURA(%s)", describe(msg)) end)
  end
  local f = CreateFrame("Frame")
  f:RegisterUnitEvent("UNIT_AURA", "player")
  f:SetScript("OnEvent", function(_, _, _, info)
    if not aw then return end
    if type(info) ~= "table" or describe(info) == "secret" then awLog("UNIT_AURA info=%s", describe(info)); return end
    -- In combat the lists are SECRET tables (bugsack 2026-10-09: `#t` threw
    -- and the line was never logged): name them, never measure or index them.
    local function open(t) return type(t) == "table" and describe(t) ~= "secret" end
    local function n(t) if open(t) then return describe(#t) end return describe(t) end
    local removed = info.removedAuraInstanceIDs
    awLog("UNIT_AURA full=%s added=%s updated=%s removed=%s removed[1]=%s",
      describe(info.isFullUpdate), n(info.addedAuras), n(info.updatedAuraInstanceIDs),
      n(removed), open(removed) and describe(removed[1]) or describe(removed))
  end)
  local c = CreateFrame("Frame")
  c:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
  c:SetScript("OnEvent", function(_, _, _, _, spellID)
    if aw then awLog("CAST %s", describe(spellID)) end
  end)
end

function Probe.AspectReport(s)
  local L = { ("Nock aspect probe  %d s  aspects: %d"):format(math.floor(GetTime() - s.t0), #s.list) }
  -- Trueshot Aura: what the cancel match compares against.
  local TSA = Nock.Spells.TRUESHOT_AURA
  local ts = s.trueshot or {}
  L[#L + 1] = ("  Trueshot Aura  id %s  name %s  SpellIcon %s  cache rec at arm: spellId %s auraInstanceID %s icon %s"):format(
    tostring(TSA), describe(Nock.API.SpellName(TSA)), describe(Nock.API.SpellIcon(TSA)),
    describe(ts.spellId), describe(ts.auraInstanceID), describe(ts.icon))
  for _, a in ipairs(s.list) do
    local slots = {}
    for i, v in ipairs(a.slots) do slots[i] = tostring(v) end
    L[#L + 1] = ("  %s  base %d  learned %s  slots %s"):format(a.name, a.base, tostring(a.id),
      #slots > 0 and table.concat(slots, ",") or "-")
  end
  L[#L + 1] = "-- log (t, change or event):"
  for i = 1, #s.L do L[#L + 1] = s.L[i] end
  return table.concat(L, "\n")
end

function Probe:AspectWatch(rest)
  local function finish()
    if not aw then return end
    local s = aw
    aw = nil
    if s.ticker then s.ticker:Cancel() end
    local text = Probe.AspectReport(s)
    if Nock.UI and Nock.UI.ShowCopyBox then Nock.UI.ShowCopyBox(text) else Nock:Print(text) end
  end
  if rest == "stop" then finish(); return end
  local T = _G.C_Timer
  if not (T and T.NewTicker) then Nock:Print("No ticker on this client."); return end
  if aw then finish() end
  awInstallHooks()
  awHookButtons()
  aw = { t0 = GetTime(), L = {}, list = awAspects(), last = {}, cur = {} }
  -- The Trueshot aura as the cache sees it now (arm out of combat).
  local AC, TSA = Nock.AuraCache, Nock.Spells.TRUESHOT_AURA
  local rec = AC and AC.BySpell and AC.BySpell("player", TSA)
  if not rec and AC and AC.ByName then
    local n = Nock.Flavor.Plain(Nock.API.SpellName(TSA))
    if type(n) == "string" then rec = AC.ByName("player", n) end
  end
  aw.trueshot = rec and { spellId = rec.spellId, auraInstanceID = rec.auraInstanceID, icon = rec.icon } or nil
  local s = aw
  local ticks = 0
  s.ticker = T.NewTicker(0.25, function()
    if aw ~= s then return end
    ticks = ticks + 1
    awSample(s.list, s.cur)
    for k, v in pairs(s.cur) do
      if s.last[k] ~= v then awLog("%s = %s", k, v); s.last[k] = v end
    end
    if ticks % 8 == 0 then awHookButtons() end -- buttons made mid-fight
    if ticks >= ASPECT_SECONDS * 4 then finish() end
  end)
  Nock:Print(("Aspect probe armed for %d s: pull, cancel your aspect by right-click (and once by macro), then /nock probe aspect stop."):format(ASPECT_SECONDS))
end

function Probe:Show(which, rest)
  local text
  if which == "aspect" then self:AspectWatch(rest); return end
  if which == "range" then self:RangeRecord(rest); return end
  if which == "keys" then self:KeysRecord(rest); return end
  if which == "camera" then
    local CF = Nock:GetModule("CameraFlip", true)
    if CF then CF:Command(rest) else Nock:Print("The camera flip is only available on WoW Forever.") end
    return
  end
  if which == "fonts" then self:FontPreview(rest); return end
  if which == "weave" then
    local WH, ST = Nock:GetModule("WeaveHelper", true), Nock:GetModule("SwingTimer", true)
    local st = WH and WH.st or {}
    local plainMoving = _G.IsPlayerMoving and Nock.Flavor.Plain(_G.IsPlayerMoving())
    local text = Probe.WeaveReport({
      stage = st.stage, legIn = st.legIn, legOut = st.legOut, learnedIn = st.learnedIn, learnedOut = st.learnedOut,
      legOutBack = st.legOutBack, learnedOutBack = st.learnedOutBack,
      moving = st.moving, playerMovingPlain = type(plainMoving) == "boolean",
      radial = st.radial, face = st.face, pos = st.pos, shootFrac = st.shootFrac, learnedFrac = st.learnedFrac,
      mhRangeEvents = WH and WH.mhRangeEvents or 0,
      raptorId = Nock.Spells and Nock.Spells.RAPTOR_STRIKE,
      helper = (WH and WH.Samples) and WH:Samples() or {},
      transitions = (WH and WH.Transitions) and WH:Transitions() or {},
      swings = (ST and ST.Samples) and ST:Samples() or {}, casts = self.Casts and self:Casts() or {},
    })
    if Nock.UI and Nock.UI.ShowCopyBox then Nock.UI.ShowCopyBox(text) else Nock:Print(text) end
    return
  end
  -- `/nock probe idshape set|list`: re-filter the live buff row with the
  -- other ID-table shape (Forever/AuraRow.lua ID_SHAPE, unverified). Put a
  -- buff that is up on the hide list, then flip until it disappears.
  -- `/nock probe ring`: the aspect ring's secure inputs vs the live screen
  -- (the drawn ring landed away from the cursor, 2026-09-26).
  if which == "ring" then
    local b, h, layer = _G.NockAspectRingButton, _G.NockAspectRingScreen, _G.NockAspectRingLayer
    local L = {}
    local function row(k, v) L[#L + 1] = ("%s: %s"):format(k, tostring(v)) end
    row("stored sw, sh", b and (tostring(b:GetAttribute("sw")) .. ", " .. tostring(b:GetAttribute("sh"))) or "no button")
    row("live UIParent w, h", ("%.1f, %.1f"):format(UIParent:GetWidth(), UIParent:GetHeight()))
    row("stored scale, dead", b and (tostring(b:GetAttribute("scale")) .. ", " .. tostring(b:GetAttribute("dead"))) or "-")
    if h then
      local l, bo, w, hh = h:GetRect()
      row("header rect (l, b, w, h)", ("%s, %s, %s, %s"):format(tostring(l), tostring(bo), tostring(w), tostring(hh)))
      row("header scale / effective", ("%s / %s"):format(tostring(h:GetScale()), tostring(h:GetEffectiveScale())))
    end
    row("UIParent effective scale", UIParent:GetEffectiveScale())
    local cx, cy = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    row("cursor in UIParent units", ("%.1f, %.1f"):format(cx / s, cy / s))
    if layer then
      local n = layer:GetNumPoints()
      for i = 1, n do
        local p, rel, rp, x, y = layer:GetPoint(i)
        row("layer point " .. i, ("%s %s %s %.1f %.1f"):format(tostring(p), rel and rel:GetName() or "?", tostring(rp), x or 0, y or 0))
      end
      row("layer scale / effective", ("%s / %s"):format(tostring(layer:GetScale()), tostring(layer:GetEffectiveScale())))
    end
    local text = table.concat(L, "\n")
    if Nock.UI and Nock.UI.ShowCopyBox then Nock.UI.ShowCopyBox(text) else Nock:Print(text) end
    return
  end
  -- `/nock probe secure`: do secure snippets run on this client now (dead on
  -- 2026-09-24, loadstring_untainted = nil)? Each step is reported: the
  -- restricted loader, an Execute that writes an attribute, a snippet that
  -- reads the cursor (the in-combat aspect ring needs it) and a wrapped
  -- OnClick. Run it out of combat AND in combat.
  if which == "secure" then
    local text = Probe.SecureReport()
    if Nock.UI and Nock.UI.ShowCopyBox then Nock.UI.ShowCopyBox(text) else Nock:Print(text) end
    return
  end
  -- `/nock probe usable [id]`: is a spell's usability plain or secret right
  -- now (run it in combat too)? Default Mongoose Bite; also what its grid
  -- tile holds and which secret-safe setters the client has.
  if which == "usable" then
    local id = tonumber(rest) or 1495
    local isSecret = _G.issecretvalue
    local okc, u, m = pcall(Nock.API.SpellUsable, id)
    local function show(v)
      if isSecret and isSecret(v) then return "SECRET" end
      return tostring(v)
    end
    local L = {
      ("spell %d (%s)  in combat: %s"):format(id, tostring(Nock.Flavor.Plain(Nock.API.SpellName(id))),
        tostring(InCombatLockdown and InCombatLockdown() or false)),
      okc and ("usable: %s  noMana: %s"):format(show(u), show(m)) or ("error: " .. tostring(u)),
      ("reactive: %s"):format(tostring(Nock.API.IsReactiveSpell(id))),
    }
    for key, s in pairs(Nock.state and Nock.state.cooldowns or {}) do
      if s.spellId and Nock.API.IsReactiveSpell(s.spellId) then
        L[#L + 1] = ("tile %s: spell %s  usable %s  reactive %s"):format(key, tostring(s.spellId), tostring(s.usable), tostring(s.reactive))
      end
    end
    local tex = UIParent and UIParent.CreateTexture and UIParent:CreateTexture()
    L[#L + 1] = ("SetVertexColorFromBoolean: %s  SetAlphaFromBoolean: %s"):format(
      tostring(tex and tex.SetVertexColorFromBoolean ~= nil), tostring(tex and tex.SetAlphaFromBoolean ~= nil))
    if tex then tex:Hide() end
    local text = table.concat(L, "\n")
    if Nock.UI and Nock.UI.ShowCopyBox then Nock.UI.ShowCopyBox(text) else Nock:Print(text) end
    return
  end
  -- `/nock probe talents`: every talent C_SpecializationInfo.GetTalentInfo
  -- answers for, under each spec index (0 = none given), with its spell id
  -- and rank. How the Forever tree is served is unprobed (Lone Wolf, 2026-09-26).
  if which == "talents" then
    local TC = _G.Constants and _G.Constants.TraitConsts
    local text = Probe.TraitReport({
      CT = _G.C_ClassTalents, T = _G.C_Traits, SI = _G.C_SpecializationInfo,
      name = function(id) return Nock.Flavor.Plain(Nock.API.SpellName(id)) end,
      viewID = TC and TC.VIEW_TRAIT_CONFIG_ID or -3,
    }) .. "\n\n" .. Probe.TalentReport(_G.C_SpecializationInfo and _G.C_SpecializationInfo.GetTalentInfo)
    if Nock.UI and Nock.UI.ShowCopyBox then Nock.UI.ShowCopyBox(text) else Nock:Print(text) end
    return
  end
  -- `/nock probe trackmark [Name|off]`: the track-mark fonts on a PLAIN name
  -- (default Dragonkin), every kind's string stacked down the screen centre
  -- with its clip window outlined -- proves the pictures render and the D
  -- shift clips without any secret involved. `off` hides it.
  if which == "trackmark" then
    local S = Nock.Spells
    local f = self._trackMarkTest
    if rest == "off" then
      if f then f:Hide() end
      return
    end
    -- The client capitalises its names and the markers are the capitals.
    local name = (rest ~= "" and rest) or "Dragonkin"
    name = name:sub(1, 1):upper() .. name:sub(2):lower()
    local size = 44
    local em = S.TRACK_MARK_FONT * size
    local rowH = em
    if not f then
      f = CreateFrame("Frame", "NockProbeTrackMark", UIParent)
      f:SetSize(S.TRACK_MARK_WIDTH * em + 160, 8 * (rowH + 6))
      f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
      f:SetFrameStrata("DIALOG")
      f.rows = {}
      local i = 0
      for trackId, kind in pairs(S.TRACK_MARK) do
        local win = CreateFrame("Frame", nil, f, "BackdropTemplate")
        win:SetClipsChildren(true)
        win:SetSize(S.TRACK_MARK_WIDTH * em, rowH)
        win:SetPoint("TOPLEFT", f, "TOPLEFT", 160, -i * (rowH + 6))
        Nock.UI.ApplyBackdrop(win)
        win:SetBackdropColor(0, 0, 0, 0.5)
        win:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
        local tag = f:CreateFontString(nil, "OVERLAY")
        tag:SetFont(Nock.UI.GetFont(), 12, "OUTLINE")
        tag:SetPoint("RIGHT", win, "LEFT", -8, 0)
        tag:SetText(kind)
        -- Two layers, the row's geometry. SafeSetFont: a face renders BLANK
        -- on first use until its size is bounced (ruling 2026-09-23).
        local x = S.TRACK_MARK_SHIFTED[trackId] and -S.TRACK_MARK_SHIFT * em or 0
        local function layer(drawLayer, file, r, g, b)
          local fs = win:CreateFontString(nil, drawLayer)
          fs:SetJustifyH("LEFT"); fs:SetJustifyV("MIDDLE"); fs:SetWordWrap(false)
          fs:SetTextColor(r, g, b, 1)
          fs:SetSize((S.TRACK_MARK_SHIFT + S.TRACK_MARK_WIDTH + 1) * em, rowH)
          fs:SetPoint("LEFT", win, "LEFT", x, 0)
          local path = "Interface\\AddOns\\Nock\\Media\\" .. file
          Nock.UI.SafeSetFont(fs, path, em, "")
          fs.loaded = fs:GetFont() == path
          return fs
        end
        local back = layer("ARTWORK", "NockTrackMark-" .. kind .. "-back.ttf", 0.08, 0.08, 0.08)
        local fs = layer("OVERLAY", "NockTrackMark-" .. kind .. ".ttf", 1, 0.65, 0.1)
        f.rows[#f.rows + 1] = { fs = fs, back = back, tag = tag, kind = kind }
        i = i + 1
      end
      self._trackMarkTest = f
    end
    local loaded = {}
    for _, r in ipairs(f.rows) do
      r.fs:SetText(name)
      r.back:SetText(name)
      loaded[#loaded + 1] = r.kind .. "=" .. tostring(r.fs.loaded and r.back.loaded)
    end
    f:Show()
    Nock:Print(("Track mark test: '%s' in every kind (font loaded: %s). `/nock probe trackmark off` hides it."):format(name, table.concat(loaded, " ")))
    return
  end
  if which == "tracking" then
    local TM = Nock:GetModule("Tracking", true)
    -- `/nock probe tracking any`: toggle the warning free of the talent
    -- (rank 1 published) for testing; back to the tree on /reload or again.
    if rest == "any" and TM then
      TM.ignoreTalent = not TM.ignoreTalent or nil
      TM._rankAt = nil
      Nock:Print(("Tracking warning: %s"):format(TM.ignoreTalent and "ignoring the talent (testing)" or "talent required again"))
      return
    end
    local R = TM and TM.Reads
    local S, Tr = Nock.Spells, Nock.Traits
    local nameOf = function(id) return Nock.Flavor.Plain(Nock.API.SpellName(id)) end
    -- Every target read raw: SECRET, ERR:<msg>, or the value (a creature type
    -- that is secret in an instance reads nil through Flavor.Plain).
    local isSecret = _G.issecretvalue
    local function raw(fn, ...)
      if type(fn) ~= "function" then return "missing" end
      local ok, v = pcall(fn, ...)
      if not ok then return "ERR:" .. tostring(v) end
      if isSecret and v ~= nil and isSecret(v) then return "SECRET" end
      return v
    end
    local rawReads = {
      { "InCombat", raw(_G.InCombatLockdown) }, { "IsInInstance", raw(_G.IsInInstance) },
      { "UnitExists", raw(_G.UnitExists, "target") }, { "UnitName", raw(_G.UnitName, "target") },
      { "UnitGUID", raw(_G.UnitGUID, "target") },
      { "UnitCreatureType", raw(_G.UnitCreatureType, "target") },
      { "UnitCreatureType.id", raw(function() return select(2, UnitCreatureType("target")) end) },
      { "UnitCreatureFamily", raw(_G.UnitCreatureFamily, "target") },
      { "UnitClassification", raw(_G.UnitClassification, "target") },
      { "UnitCanAttack", raw(_G.UnitCanAttack, "player", "target") },
      { "UnitIsDead", raw(_G.UnitIsDead, "target") },
      { "UnitIsPlayer", raw(_G.UnitIsPlayer, "target") },
      { "UnitCreatureType(mouseover)", raw(_G.UnitCreatureType, "mouseover") },
      { "UnitCreatureType(pet)", raw(_G.UnitCreatureType, "pet") },
    }
    -- The tooltip's own lines: the creature type sits on one of them.
    local TI = _G.C_TooltipInfo
    if TI and TI.GetUnit then
      local okt, tip = pcall(TI.GetUnit, "target")
      if okt and type(tip) == "table" and type(tip.lines) == "table" then
        for i, line in ipairs(tip.lines) do
          if i > 6 then break end
          rawReads[#rawReads + 1] = { "tip" .. i, raw(function() return line.leftText end) }
        end
      else
        rawReads[#rawReads + 1] = { "tooltip", okt and tostring(tip) or ("ERR:" .. tostring(tip)) }
      end
    else
      rawReads[#rawReads + 1] = { "tooltip", "C_TooltipInfo.GetUnit missing" }
    end
    -- The auto-switch: the toggle, whether one is armed, the last one sent.
    if TM then
      local p = Nock.db and Nock.db.profile or {}
      rawReads[#rawReads + 1] = { "auto", ("%s  armed %s  last spell %s row %s ok %s %s"):format(
        p.trackingAutoSwitch == true and "ON" or "off", tostring(TM._autoArmed == true),
        tostring(TM._autoLastId), tostring(TM._autoLastIndex), tostring(TM._autoLastOk),
        TM._autoLastAt and ("%.1fs ago"):format(GetTime() - TM._autoLastAt) or "") }
      rawReads[#rawReads + 1] = { "SetTracking", tostring(_G.C_Minimap and _G.C_Minimap.SetTracking ~= nil) }
    end
    -- The in-instance flare's plain half (Forever/Warnings.lua TrackMark).
    local WM = Nock:GetModule("Warnings", true)
    if WM and WM.TrackMark then
      local okm, m = pcall(WM.TrackMark, WM)
      if okm and type(m) == "table" then
        rawReads[#rawReads + 1] = { "mark.text", (m.text ~= nil and isSecret and isSecret(m.text)) and "SECRET" or m.text }
        local ids = {}
        for id in pairs(m.show) do ids[#ids + 1] = tostring(id) end
        table.sort(ids)
        rawReads[#rawReads + 1] = { "mark.show", #ids > 0 and table.concat(ids, ",") or "none" }
      else
        rawReads[#rawReads + 1] = { "mark", "ERR:" .. tostring(m) }
      end
      local WV = Nock:GetModule("WarningsView", true)
      local tm = WV and WV.trackMark
      if tm then
        local shown = {}
        for id, s in pairs(tm.strings) do if s.fs:IsShown() then shown[#shown + 1] = tostring(id) end end
        table.sort(shown)
        rawReads[#rawReads + 1] = { "mark.strings", ("%d built, shown %s, font %s, window %.0fx%.0f"):format(
          (function() local c = 0; for _ in pairs(tm.strings) do c = c + 1 end; return c end)(),
          #shown > 0 and table.concat(shown, ",") or "none",
          tostring(tm.strings[19883] and (tm.strings[19883].fs:GetFont())), tm.window:GetWidth(), tm.window:GetHeight()) }
      end
    end
    -- Can a curve turn the secret creature type id into a displayable alpha
    -- (the pet HP square's trick)? No (2026-09-30, in a dungeon): a curve's
    -- Evaluate takes a secret only during untainted execution, and the only
    -- APIs that evaluate a curve for an addon are UnitHealthPercent and
    -- UnitPowerPercent. Kept so a client change shows up here first.
    rawReads[#rawReads + 1] = { "curveEval", raw(function()
      local c = C_CurveUtil.CreateCurve()
      c:SetType(Enum.LuaCurveType.Step)
      c:AddPoint(0, 0); c:AddPoint(7, 1); c:AddPoint(8, 0)
      local _, id = UnitCreatureType("target")
      return c:Evaluate(id)
    end) }
    local text = Probe.TrackingReport({
      list = R and R.trackingList(), creatureType = R and R.creatureType(), typeNames = R and R.creatureTypeNames(),
      raw = rawReads,
      rank = Tr and Tr.LiveRank(S.IMPROVED_TRACKING, S.IMPROVED_TRACKING_NAME), improvedId = S.IMPROVED_TRACKING,
      talents = Tr and Tr.Find("Track", _G.C_ClassTalents, _G.C_Traits, nameOf) or {},
      state = Nock.state and Nock.state.tracking,
    })
    if Nock.UI and Nock.UI.ShowCopyBox then Nock.UI.ShowCopyBox(text) else Nock:Print(text) end
    return
  end
  -- `/nock probe lonewolf`: is Lone Wolf seen as talented, and by which path
  -- (spellbook / talent / aura)? Out of combat.
  if which == "lonewolf" then
    local PM = Nock:GetModule("ForeverPet", true)
    if not (PM and PM.LoneWolf) then return end
    PM._loneWolfAt = nil
    local on = PM:LoneWolf(false)
    Nock:Print(("Lone Wolf: %s%s"):format(on and "talented" or "not seen",
      on and (" (via " .. tostring(PM._loneWolfHow) .. ")") or ""))
    return
  end
  if which == "idshape" then
    local AR = Nock.ForeverAuraRow
    if not AR then return end
    AR.lastApply = nil
    if rest == "set" or rest == "list" then
      AR.ID_SHAPE = rest
      Nock:SendMessage("NOCK_VISUALS_CHANGED")
    end
    local p = Nock.db and Nock.db.profile or {}
    local function ids(t)
      local out = {}
      for i = 1, #(t or {}) do out[#out + 1] = tostring(t[i]) end
      return #out > 0 and table.concat(out, ", ") or "(empty)"
    end
    local lines = {
      ("ID shape: %s"):format(AR.ID_SHAPE),
      ("hidden: %s"):format(ids(p.foreverBuffHide)),
      ("pinned: %s"):format(ids(p.reactBuffCustom)),
      ("in combat: %s"):format(tostring(InCombatLockdown and InCombatLockdown() or false)),
      ("apply: %s"):format(AR.lastApply or "not run (no row, in combat, or no shape given)"),
    }
    local text = table.concat(lines, "\n")
    if Nock.UI and Nock.UI.ShowCopyBox then Nock.UI.ShowCopyBox(text) else Nock:Print(text) end
    return
  end
  -- `/nock probe cdcatalog`: every spellbook and talent spell with the
  -- client's cooldown signals, for the discovered cooldown catalog. Out of combat.
  if which == "cdcatalog" then
    text = Probe.CdCatalogReport(Nock.CooldownDiscovery.ClientApi())
    if Nock.UI and Nock.UI.ShowCopyBox then Nock.UI.ShowCopyBox(text) else Nock:Print(text) end
    return
  end
  if which == "spells" then text = self:SpellbookReport()
  elseif which == "frames" then text = self:FramesReport()
  elseif which == "container" then
    text = self:ContainerSpike()
  elseif which == "sting" then
    text = self:StingSpike(rest)
  elseif which == "aura" then
    local name, id = (rest or ""):match("^(.-)%s*(%d*)$")
    if name == "" then name = "Quick Shots" end
    self:WatchAura(name, tonumber(id) or 6150)
    return
  else text = self:Report() end
  if Nock.UI and Nock.UI.ShowCopyBox then Nock.UI.ShowCopyBox(text) else Nock:Print(text) end
end
