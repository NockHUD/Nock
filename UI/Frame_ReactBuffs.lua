-- UI/Frame_ReactBuffs.lua
-- React-mode buff row: the reference WA pack's "Important Buffs" (haste/burst
-- procs) and "Dynamic utility buffs" sections UNIFIED into one center-growing
-- icon row glued above the React cluster by default, and freely placeable
-- against it (drag / nudge pad while unlocked, ReactCorners convention) for
-- anyone who wants it under the HUD instead (rarely more than a handful are up
-- at once, so one row reads better than two). Replaces the classic
-- BuffTracker/TotemTracker panels while React mode is active (their views
-- gate themselves off; the TotemTracker ENGINE keeps running so state.totems
-- stays fresh) and adds Nock's Windfury weapon-enchant slot, which the
-- reference pack lacks (it only covers Grace of Air).

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local ReactBuffs = Nock:NewModule("ReactBuffs", "AceEvent-3.0")
local C = Nock.Constants

-- Shared empty table for the per-entry disable reads (never written).
local EMPTY = {}

-- Fixed React skin (Frame_ReactCluster.lua convention): hardcoded numbers,
-- deliberately NOT registered with the LSM/profile styling hooks. The slot box
-- itself (colors, fonts, countdown formatting) now lives in
-- Nock.UI.CreateReactSlot / PaintReactSlot, shared with the React corner icons.
local REACT = {
  ICON     = 26,
  GAP      = -1,     -- 1px border-overlap seams (grid convention)
  LIFT     = 20,     -- clearance above the cluster top: the glued cast bar
                     -- occupies 16px there, so the row never overlaps it
}
-- 10 slots x (26-1)px = 249px vs the 240px default cluster width: the last
-- slot overhangs symmetrically by ~5px per side in the (rare) full-house
-- moment; anything past 10 simultaneous buffs is dropped.
local MAX_ICONS = 10
local GROUP_SCAN_SEC = 0.5   -- LotP / Grace-of-Air subgroup sweep cadence
-- Frenzy alert mode: seconds the proc must have been down before the slot
-- says MISSING. Frenzy is an 8 s proc off pet crits that usually re-procs
-- within a swing or two; without a grace the grey flickers on every gap and
-- teaches you to ignore it. With it, grey means it actually dropped.
local FRENZY_GRACE = 2.0

-- Dual-form spell lookups (TotemTracker convention; Anniversary may expose
-- bare globals or C_Spell.*).
local function spellName(id)
  if GetSpellInfo then local n = GetSpellInfo(id); if n then return n end end
  if C_Spell and C_Spell.GetSpellInfo then
    local i = C_Spell.GetSpellInfo(id); if i then return i.name end
  end
  return nil
end
local function spellIcon(id)
  if C_Spell and C_Spell.GetSpellTexture then
    local t = C_Spell.GetSpellTexture(id); if t then return t end
  end
  if GetSpellTexture then local t = GetSpellTexture(id); if t then return t end end
  if GetSpellInfo then local _, _, ic = GetSpellInfo(id); if ic then return ic end end
  return nil
end

-- Reused item pool — entry tables are created once and overwritten in place
-- (no per-tick allocation). `n` is the live length; entries past it are stale.
local function addItem(t, icon, exp, dur, label, desat)
  if t.n >= MAX_ICONS then return end
  local n = t.n + 1
  local it = t[n]
  if not it then it = {}; t[n] = it end
  it.icon  = icon
  it.exp   = exp or 0
  it.dur   = dur or 0
  it.label = label
  it.desat = desat and true or false
  t.n = n
end

function ReactBuffs:OnInitialize()
  -- Glued onto the React cluster (ReactCastBar convention): matches
  -- reactWidth/reactScale, follows free-layout drags, vanishes with the
  -- cluster in classic mode.
  local cluster = Nock:GetModule("ReactCluster", true)
  local parent  = (cluster and cluster.frame) or Nock.parentFrame
  local panel = CreateFrame("Frame", "NockReactBuffs", parent)
  panel:SetHeight(REACT.ICON)
  panel:Hide()
  self.frame   = panel
  self._parent = parent

  self._slots = {}
  for i = 1, MAX_ICONS do
    self._slots[i] = Nock.UI.CreateReactSlot(panel, "NockReactBuff" .. i, REACT.ICON)
  end
  self._items = { n = 0 }

  -- Unlock-mode frame (cast-bar convention): the row is invisible whenever no
  -- proc is up, which is exactly when the user is laying out the HUD -- so
  -- while unlocked, Refresh paints placeholder procs and this border marks
  -- the row's footprint. It is also what makes the row grabbable: with no proc
  -- up there would be nothing under the cursor to start a drag on.
  local editBG = CreateFrame("Frame", nil, panel, "BackdropTemplate")
  editBG:SetAllPoints(panel)
  editBG:SetFrameLevel(math.max(0, panel:GetFrameLevel() - 1))
  Nock.UI.ApplyBackdrop(editBG)
  editBG:SetBackdropColor(0, 0, 0, 0.25)
  editBG:SetBackdropBorderColor(unpack(C.COLORS.BORDER_UNLOCK))
  editBG:Hide()
  self.editBG = editBG

  self._grpAt = 0
  self._lotpInGroup, self._goaInGroup, self._shamanInSub = false, false, false

  self:SetupMove()
  self:ApplyLayout()
  self:ApplyLock()
  self:RegisterMessage("NOCK_LOCK_CHANGED", "ApplyLock")
end

-- ONE module, TWO hosts. React: the row is the cluster's, welded above its cast
-- bar or at reactBuffRowPos (cluster-relative). Classic: the same frame is the
-- HUD frame's, welded above the classic cast bar or at classicBuffRowPos
-- (HUD-relative), behind showBuffRow and scaled by buffRowScale — floating
-- OUTSIDE the box and freely movable, exactly like the React one (user,
-- 2026-08-27; a first cut as a cascade row put it inside the box). The scan
-- and the paint are the same code either way — that is what keeps the two
-- looks identical.
-- Which HUD look hosts the row right now: "classic" | "react" | "fluffy".
-- ONE frame, three hosts — everything host-dependent (parent, master switch,
-- position store, weld lift, scale) resolves through this and the three
-- accessors below; an unknown future mode files as classic, matching
-- Nock.HudIsClassic's bucket.
function ReactBuffs:Host()
  local m = Nock.HudMode()
  if m == "react" or m == "fluffy" then return m end
  return "classic"
end

function ReactBuffs:IsClassicHost()
  return self:Host() == "classic"
end

-- The mode's own master switch: reactBuffRows in React, fluffyBuffRows in
-- Fluffy, showBuffRow in Classic.
function ReactBuffs:IsEnabled()
  local p = Nock.db and Nock.db.profile
  if not p then return false end
  local host = self:Host()
  if host == "classic" then return p.showBuffRow ~= false end
  if host == "fluffy" then return p.fluffyBuffRows ~= false end
  return p.reactBuffRows ~= false
end

-- The row's height (the slot size).
function ReactBuffs:ContentHeight()
  return REACT.ICON
end

-- The frame the row hangs from in the current mode: the React cluster in
-- React, the fluffy cluster in Fluffy, the HUD frame in Classic. The fluffy
-- cluster is resolved live (its module loads after this one in the TOC).
function ReactBuffs:HostFrame()
  local host = self:Host()
  if host == "classic" then return Nock.parentFrame end
  if host == "fluffy" then
    local m = Nock:GetModule("FluffyCluster", true)
    return (m and m.frame) or Nock.parentFrame
  end
  return self._parent or Nock.parentFrame
end

-- The profile key holding the mode's free position (false = welded default).
function ReactBuffs:PosKey()
  local host = self:Host()
  if host == "classic" then return "classicBuffRowPos" end
  if host == "fluffy" then return "fluffyBuffRowPos" end
  return "reactBuffRowPos"
end

-- The Classic weld's lift: clear of the classic cast bar, which sits on the
-- HUD's top edge (y -1) at castBarHeight + 2 x padding, plus a 4 px gap —
-- the same "just above the cast bar" the React weld keeps.
function ReactBuffs:ClassicLift()
  local p = Nock.db and Nock.db.profile or {}
  local h   = tonumber(p.castBarHeight) or C.DIM.CAST_BAR_H
  local pad = tonumber(p.castBarPadding) or C.DIM.OUTER_PAD
  return (h + 2 * pad) - 1 + 4
end

-- Host-relative screen capture (ReactCorners:CaptureClusterPos): after a
-- drag the live anchor is wherever StartMoving left it, so re-derive a stable
-- BOTTOMLEFT-to-BOTTOMLEFT offset from edge coordinates. Edge reads are in
-- each frame's OWN scaled space; in React row and cluster share a scale so
-- the plain subtraction is exact, in Classic the row wears buffRowScale, so
-- the host's edge is brought into the row's space first (SetPoint offsets
-- are read in the child's space).
function ReactBuffs:CaptureClusterPos()
  local parent, panel = self:HostFrame(), self.frame
  if not (parent and panel:GetLeft() and parent:GetLeft()) then return nil end
  local k = 1
  if panel.GetEffectiveScale and parent.GetEffectiveScale then
    local es, hs = panel:GetEffectiveScale(), parent:GetEffectiveScale()
    if es and hs and es > 0 then k = hs / es end
  end
  return { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT",
           x = panel:GetLeft()   - parent:GetLeft()   * k,
           y = panel:GetBottom() - parent:GetBottom() * k }
end

-- Drag + nudge-pad wiring (ReactCorners:SetupMove). The stored position stays
-- cluster-relative, so no `capture` override is needed for the pad: the weld's
-- own GetPoint() already reports against the cluster, which is exactly the
-- space set()/ApplyLayout re-anchor in.
function ReactBuffs:SetupMove()
  local view  = self
  local panel = self.frame
  panel:SetMovable(true)
  panel:SetClampedToScreen(true)
  panel:RegisterForDrag("LeftButton")
  panel:EnableMouse(false)
  panel:SetScript("OnDragStart", function(f) f:StartMoving() end)
  panel:SetScript("OnDragStop", function(f)
    f:StopMovingOrSizing()
    -- Host-relative either way: the cluster's in React, the HUD's in Classic
    -- (each mode has its own key, so a drag in one never moves the other).
    local pos = view:CaptureClusterPos()
    if pos then Nock.db.profile[view:PosKey()] = pos end
    view:ApplyLayout()
  end)
  -- One pad for the frame, mode-aware: the position key follows the host.
  Nock.UI.RegisterNudgeable(panel, {
    label  = "Buff Row",
    active = function() return view:IsEnabled() end,
    get    = function() return Nock.db.profile[view:PosKey()] end,
    set    = function(pos)
      Nock.db.profile[view:PosKey()] = pos
      view:ApplyLayout()
    end,
    -- false re-welds the row above the mode's cast bar: that IS its default.
    default = function() return false end,
  })
end

-- Unlocked = draggable; locked = mouse-transparent so combat clicks pass
-- through the (invisible) row. The slot children never take the mouse.
function ReactBuffs:ApplyLock()
  self.frame:EnableMouse(not Nock.IsLocked())
end

-- THE single place the row anchors.
--
-- Welded (no stored position): stretched across the cluster's top edge at the
-- dynamic lift — an overridden cast-bar height (reactCastH) taller than the
-- reference would collide with the row at the fixed LIFT, so keep 4px above
-- whatever the glued cast bar occupies.
--
-- Free (dragged / nudged): ONE cluster-relative point, which means the stretch
-- no longer supplies a width — set it explicitly from the cluster, or the row
-- keeps whatever width it last had and the centered icon layout drifts.
--
-- Classic host: the same two shapes against the HUD frame — welded across its
-- top edge above the classic cast bar (ClassicLift), or at classicBuffRowPos —
-- under buffRowScale (the row is not a cascade row, so nothing else scales it;
-- a two-point weld's offsets are read in the child's space, hence / s).
function ReactBuffs:ApplyLayout()
  local p       = Nock.db and Nock.db.profile
  local panel   = self.frame
  local classic = self:IsClassicHost()
  local parent  = self:HostFrame() or panel:GetParent()
  if parent and panel:GetParent() ~= parent then panel:SetParent(parent) end

  local s = 1
  if classic then
    local v = p and tonumber(p.buffRowScale)
    if v and v > 0 then s = v end
  end
  panel:SetScale(s)

  local pos = p and p[self:PosKey()]
  panel:ClearAllPoints()
  if type(pos) == "table" and pos.point then
    local w = parent and parent:GetWidth()
    if w and w > 0 then panel:SetWidth(w / s) end
    panel:SetPoint(pos.point, parent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
  else
    local lift
    local host = self:Host()
    if host == "classic" then
      lift = self:ClassicLift()
    elseif host == "fluffy" then
      -- The fluffy cast bar is a transient strip welded above the cluster —
      -- keep 4px above whatever height it occupies when it appears.
      local castH = p and tonumber(p.fluffyCastH) or 14
      lift = math.max(18, castH + 4)
    else
      local castH = p and tonumber(p.reactCastH) or 16
      lift = math.max(REACT.LIFT, castH + 4)
    end
    panel:SetPoint("BOTTOMLEFT",  parent, "TOPLEFT",  0, lift / s)
    panel:SetPoint("BOTTOMRIGHT", parent, "TOPRIGHT", 0, lift / s)
  end
end

function ReactBuffs:OnEnable()
  local RB = C.REACT_BUFFS
  self:RebuildImportantIds()
  self:RegisterMessage("NOCK_VISUALS_CHANGED", "OnVisualsChanged")
  -- Utility name-sets carry the entry's STABLE KEY as the value (not just
  -- true), so a match knows which reactBuffDisabled toggle governs it.
  self._playerNames, self._petNames, self._lotpNames = {}, {}, {}
  local function put(set, id, key)
    local n = spellName(id)
    if n then set[n] = key end
  end
  put(self._playerNames, C.SpellID.FEIGN_DEATH, "feign")
  put(self._playerNames, C.SpellID.MISDIRECTION, "misdirect")
  -- The Feed Pet Effect can sit on the PLAYER or the pet depending on the
  -- client (same dual check Frame_PetStatus does) — match it on both scans.
  put(self._playerNames, RB.FEED_PET, "feedPet")
  put(self._petNames, RB.MEND_PET, "mendPet")
  put(self._petNames, RB.FEED_PET, "feedPet")
  put(self._petNames, RB.INTIMIDATION_BUFF, "intimidation")
  put(self._petNames, RB.FRENZY, "frenzy")
  put(self._lotpNames, RB.LOTP, true)
  put(self._lotpNames, RB.LOTP_IMP, true)
  -- Grace of Air detection is NAME-based, mirroring TotemTracker's
  -- AIR_TOTEM_BUFFS: the buff the totem applies is the AURA "Grace of Air",
  -- while C.SpellID.GRACE_OF_AIR (8835) is the totem-CAST spell — its name
  -- resolves to "Grace of Air Totem", which never matches a UnitBuff name
  -- (the "shows MISSING while buffed" bug). The resolved cast name stays in
  -- the set as a harmless belt-and-suspenders for other client locales.
  self._graceNames = { ["Grace of Air"] = true }
  local gn = spellName(C.SpellID.GRACE_OF_AIR)
  if gn then self._graceNames[gn] = true end
  self._lotpIcon  = spellIcon(RB.LOTP)
  self._graceIcon = spellIcon(C.SpellID.GRACE_OF_AIR)
  -- Frenzy alert mode needs the talent: re-read on the talent events and
  -- once the world is in (talents are not always readable at OnEnable).
  self:RegisterEvent("PLAYER_TALENT_UPDATE",     "RefreshTalents")
  self:RegisterEvent("CHARACTER_POINTS_CHANGED", "RefreshTalents")
  self:RegisterEvent("PLAYER_ENTERING_WORLD",    "RefreshTalents")
  self:RefreshTalents()
end

-- Is the Frenzy talent taken? Scans the BM tab (tab 1 for a TBC hunter) by
-- the talent's localized name (rank 1 = C.REACT_BUFFS.FRENZY_TALENT), the
-- Improved-HM pattern in Frame_Rotation. No talent API -> assume taken.
function ReactBuffs:RefreshTalents()
  if not (GetNumTalents and GetTalentInfo) then self._frenzyTalented = true; return end
  local want = spellName(C.REACT_BUFFS.FRENZY_TALENT)
  if not want then self._frenzyTalented = true; return end
  for i = 1, GetNumTalents(1) or 0 do
    local name, _, _, _, rank = GetTalentInfo(1, i)
    if name == want then self._frenzyTalented = (rank or 0) > 0; return end
  end
  self._frenzyTalented = false
end

-- The pet's Frenzy proc, if up: icon, expiration, duration.
-- Aura reads go through Core/AuraCache.lua (every read allocates ~1.9 KB on
-- this client; this row used to walk the player twice and the pet once per
-- refresh). Module-level callbacks with scratch upvalues: no closure per scan.
local AC = Nock.AuraCache
local sc_self, sc_flagsOnly, sc_dis

function ReactBuffs:ScanPetFrenzy()
  if not (AC and UnitExists and UnitExists("pet")) then return nil end
  local a = AC.BySpell("pet", C.REACT_BUFFS.FRENZY)
  if not a then
    for name, key in pairs(self._petNames) do
      if key == "frenzy" then
        a = AC.ByName("pet", name)
        if a then break end
      end
    end
  end
  if a then return a.icon, a.expirationTime, a.duration end
  return nil
end

-- Frenzy alert mode is on when: the entry is not hidden, the talent is taken,
-- the mode asks for it (always, or on a boss target), the fight is on and the
-- pet is alive. Then the slot is ALWAYS there — bright while up, greyed while
-- down, MISSING once down past the grace — so the row never shifts on a boss.
-- Otherwise Frenzy is present-only through ScanPet (dungeons, questing).
function ReactBuffs:FrenzyAlertMode(p, state)
  if self._dis and self._dis.frenzy then return false end
  if self._frenzyTalented == false then return false end
  local mode = p.reactBuffFrenzyMode or "boss"
  if mode == "up" then return false end
  if not state.player.inCombat then return false end
  if not (UnitExists and UnitExists("pet")) then return false end
  if UnitIsDead and UnitIsDead("pet") then return false end
  if mode == "missing" then return true end
  return Nock.IsBossTarget and Nock.IsBossTarget() or false
end

-- Exact-ID proc set = the built-in IMPORTANT_IDS plus the user's own IDs
-- (reactBuffCustom, React HUD tab). Rebuilt ONLY here — never in the 10 Hz
-- Refresh lane (allocation rule).
function ReactBuffs:RebuildImportantIds()
  local merged = {}
  for id in pairs(C.REACT_BUFFS.IMPORTANT_IDS) do merged[id] = true end
  local p = Nock.db and Nock.db.profile
  local list = p and p.reactBuffCustom
  if type(list) == "table" then
    for i = 1, #list do
      local id = tonumber(list[i])
      if id then merged[id] = true end
    end
  end
  self._impIds = merged
end

function ReactBuffs:OnVisualsChanged()
  self:RebuildImportantIds()
  -- Re-run the slot skin so a reactFont change reaches the row live —
  -- SetReactSlotSize is where the React font resolves (Widgets.lua).
  for i = 1, MAX_ICONS do
    Nock.UI.SetReactSlotSize(self._slots[i], REACT.ICON)
  end
  -- Re-anchor unconditionally: reactCastH feeds the welded lift and reactWidth
  -- feeds the free row's explicit width, and both arrive through this message.
  self:ApplyLayout()
end

-- Single player-buff pass: collects Important actives (exact-ID match) and
-- FD/MD/Feed utility actives into the one shared row, plus the on-me flags
-- the range checks pivot on.
-- flagsOnly = true: only refresh the LotP / Grace on-me flags (the positional
-- alerts read them and go into the row BEFORE the player's procs); false:
-- add the proc items. Two passes over UnitBuff, both cheap, no allocation.
local function onPlayerAura(a)
  if a.isHarmful then return end
  local self, name, spellId = sc_self, a.name, a.spellId
  if sc_flagsOnly then
    if self._lotpNames[name] then self._lotpOnMe = true end
    if self._graceNames[name] then self._goaOnMe = true end
  else
    local ukey = self._playerNames[name]
    if (spellId and self._impIds[spellId]) or (ukey and not sc_dis[ukey]) then
      addItem(self._items, a.icon, a.expirationTime, a.duration)
    end
  end
end

function ReactBuffs:ScanPlayer(flagsOnly)
  if flagsOnly then self._lotpOnMe, self._goaOnMe = false, false end
  if not AC then return end
  sc_self, sc_flagsOnly, sc_dis = self, flagsOnly, self._dis or EMPTY
  AC.ForEach("player", onPlayerAura)
end

-- A live, attackable target the bow cannot reach: RangeFinder's legacy zone
-- "OUT" (shoot probe false, not near melee). Nothing to say without a target
-- or with a dead one; the zone alone is trusted for the rest.
function ReactBuffs:TargetOutOfRange(state)
  local t = state.target
  if not t or t.rangeZone ~= "OUT" then return false end
  if not (UnitExists and UnitExists("target")) then return false end
  if UnitCanAttack and not UnitCanAttack("player", "target") then return false end
  if UnitIsDeadOrGhost and UnitIsDeadOrGhost("target") then return false end
  return true
end

local function onPetAura(a)
  if a.isHarmful then return end
  local self, dis, spellId = sc_self, sc_dis, a.spellId
  local ukey = self._petNames[a.name]
  -- Bestial Wrath lives on the PET, not the player (the player only carries
  -- an aura when talented The Beast Within), so the player-ID scan can never
  -- see it — match it here by exact ID, same convention as ScanPlayer.
  -- Frenzy (the pet's crit proc) likewise: by name through _petNames, and
  -- by id as a belt-and-braces for a client whose aura name differs.
  local isFrenzy = (ukey == "frenzy") or spellId == C.REACT_BUFFS.FRENZY
  if isFrenzy then
    -- Alert mode already seated it at the front of the row.
    if not dis.frenzy and not self._frenzyAlert then addItem(self._items, a.icon, a.expirationTime, a.duration) end
  elseif (ukey and not dis[ukey]) or spellId == C.SpellID.BESTIAL_WRATH then
    addItem(self._items, a.icon, a.expirationTime, a.duration)
  end
end

function ReactBuffs:ScanPet()
  if not (AC and UnitExists and UnitExists("pet")) then return end
  sc_self, sc_dis = self, self._dis or EMPTY
  AC.ForEach("pet", onPetAura)
end

-- Subgroup sweep for the LotP / Grace-of-Air RANGE and MISSING states. Both
-- auras are SUBGROUP-scoped in a raid (same rule as drums — see the drums
-- badge in Frame_Cooldowns), so party1-4 don't resolve there: find members
-- sharing the player's subgroup via GetRaidRosterInfo. Throttled — 5 unit
-- buff scans at 2 Hz, only consumed in combat.
local RAID_UNITS, PARTY_UNITS = {}, {}
for i = 1, 40 do RAID_UNITS[i] = "raid" .. i end
for i = 1, 4  do PARTY_UNITS[i] = "party" .. i end

function ReactBuffs:ScanGroupUnit(u)
  if not (UnitExists and UnitExists(u)) then return end
  if not self._shamanInSub and UnitClass then
    local _, cls = UnitClass(u)
    if cls == "SHAMAN" then self._shamanInSub = true end
  end
  if self._lotpInGroup and self._goaInGroup then return end
  for i = 1, 40 do
    local name = UnitBuff(u, i)
    if not name then break end
    if self._lotpNames[name] then self._lotpInGroup = true end
    if self._graceNames[name] then self._goaInGroup = true end
    if self._lotpInGroup and self._goaInGroup then break end
  end
end

function ReactBuffs:ScanGroup(now)
  if now - self._grpAt < GROUP_SCAN_SEC then return end
  self._grpAt = now
  self._lotpInGroup, self._goaInGroup, self._shamanInSub = false, false, false
  -- IsInRaid() is unreliable on this client; GetNumRaidMembers is the
  -- dependable raid signal (same fallback the other group scans use).
  local numRaid = (GetNumRaidMembers and GetNumRaidMembers()) or 0
  if numRaid > 0 and GetRaidRosterInfo then
    local mySub
    for i = 1, numRaid do
      if UnitIsUnit(RAID_UNITS[i], "player") then
        mySub = select(3, GetRaidRosterInfo(i))
        break
      end
    end
    for i = 1, numRaid do
      if (not mySub or select(3, GetRaidRosterInfo(i)) == mySub)
         and not UnitIsUnit(RAID_UNITS[i], "player") then
        self:ScanGroupUnit(RAID_UNITS[i])
      end
    end
  else
    for i = 1, 4 do self:ScanGroupUnit(PARTY_UNITS[i]) end
  end
end

-- Slow lane (Core:Tick): three 40-slot UnitBuff scans plus the throttled
-- group sweep. The countdown texts tick at exactly this 10 Hz cadence.
ReactBuffs.refreshInterval = 0.1

function ReactBuffs:Refresh(state)
  local p = Nock.db and Nock.db.profile
  if not (p and self:IsEnabled()) then
    if self.frame:IsShown() then self.frame:Hide() end
    return
  end
  if not self.frame:IsShown() then self.frame:Show() end
  -- Shown but under a hidden host (hideOoc, HUD off): the three 40-slot buff
  -- walks and the roster sweep below paint nothing anyone can see.
  if not self.frame:IsVisible() then return end
  local classic = self:IsClassicHost()

  -- Free position: a single anchor supplies no width, so keep it matched to the
  -- cluster here. ApplyLayout cannot do it alone -- at OnInitialize the cluster
  -- has not been sized yet (HUD:LayoutChildren runs later), so the width it
  -- reads on a cold login with a stored position is 0. Two GetWidth reads and a
  -- compare; the SetWidth only fires when the cluster actually changed width.
  -- Both hosts: the cluster's width in React, the HUD box's in Classic (over
  -- the row's own scale).
  local pos = p[self:PosKey()]
  if type(pos) == "table" and pos.point then
    local host = self:HostFrame()
    local pw = host and host:GetWidth()
    if pw and pw > 0 then
      local s = (classic and tonumber(p.buffRowScale)) or 1
      if s <= 0 then s = 1 end
      pw = pw / s
      if pw ~= self.frame:GetWidth() then self.frame:SetWidth(pw) end
    end
  end

  local items = self._items
  items.n = 0

  -- Edit preview: while unlocked, three representative procs (Rapid Fire,
  -- Quick Shots, Bloodlust) run through the normal layout/paint path below so
  -- the user sees exactly where live procs will appear. Spell textures resolve
  -- lazily (ReactCorners:HawkIcon convention -- a cold login may not have the
  -- spellbook yet), falling back to the question mark until they land.
  if not Nock.IsLocked() then
    if not self.editBG:IsShown() then self.editBG:Show() end
    if not self._previewIcons then
      local a = spellIcon(C.SpellID.RAPID_FIRE)
      local b = spellIcon(C.SpellID.QUICK_SHOTS)
      local c = spellIcon(C.SpellID.BLOODLUST)
      if a and b and c then self._previewIcons = { a, b, c } end
    end
    local pv = self._previewIcons
    for i = 1, 3 do
      addItem(items, (pv and pv[i]) or 134400, 0, 0)   -- 134400 = question mark
    end
  else
    if self.editBG:IsShown() then self.editBG:Hide() end
    local dis = p.reactBuffDisabled or EMPTY
    self._dis = dis

    -- ORDER MATTERS: the row drops everything past MAX_ICONS silently, and a
    -- boss pull (Lust, Drums, RF, QS, two trinkets, a potion, a racial, MD)
    -- fills it with player procs alone. So the things you can only learn
    -- HERE come first — the positional alerts, Windfury, the pet's buffs —
    -- and the player's own procs (visible on any buff frame) take what is
    -- left. Before this, WF and the Grace alert were the ones dropped.

    -- WEAVE: the weave coach's stage as a slot — Raptor Strike's icon with
    -- the stage word (GO IN / HOLD / BACK OUT / RELEASE), the row's part of
    -- the React move-in cue. Nock.UI.CoachStage is THE stage reading (the
    -- coach's committed stage, or the settings preview cycle out of combat),
    -- the same one the melee bar and the Raptor tile draw from.
    local stage = not dis.weave and Nock.UI.CoachStage(state)
    local stageLook = stage and Nock.UI.ReactStageLook(stage)
    if stageLook then
      -- Icon = what the weave is, the melee bar's own green/blue rule: Raptor
      -- Strike while Raptor is off cooldown (GO IN always is — the coach only
      -- says GO for a Raptor), the plain Attack icon on an auto-only weave
      -- (HOLD / BACK OUT / RELEASE with Raptor on cooldown). No cooldown
      -- entry (preview, cold login) reads as Raptor.
      local cd = state.cooldowns and state.cooldowns.Raptor
      local raptor = (stage == "GO") or not cd or cd.ready
      local icon
      if raptor then
        self._raptorIcon = self._raptorIcon or spellIcon(C.SpellID.RAPTOR_STRIKE)
        icon = self._raptorIcon
      else
        self._attackIcon = self._attackIcon or spellIcon(C.SpellID.ATTACK)
        icon = self._attackIcon
      end
      addItem(items, icon or 134400, 0, 0, stageLook.text, false)
    end

    -- MOVE IN: a live, attackable target outside Auto Shot range (the shoot
    -- probe false and not near melee: rangeZone "OUT", Modules/RangeFinder).
    -- No combat gate — a dummy from too far away is the everyday case.
    if not dis.movein and self:TargetOutOfRange(state) then
      self._autoIcon = self._autoIcon or spellIcon(C.SpellID.AUTO_SHOT)
      addItem(items, self._autoIcon or 134400, 0, 0, "MOVE IN", true)
    end

    -- Frenzy in alert mode (boss target by default): a fixed slot, up or down.
    local frenzyAlert = self:FrenzyAlertMode(p, state)
    self._frenzyAlert = frenzyAlert
    if frenzyAlert then
      local icon, exp, dur = self:ScanPetFrenzy()
      if icon then
        self._frenzyDownAt = nil
        addItem(items, icon, exp, dur)
      else
        local now = GetTime()
        self._frenzyDownAt = self._frenzyDownAt or now
        self._frenzyIcon = self._frenzyIcon or spellIcon(C.REACT_BUFFS.FRENZY)
        local label = (now - self._frenzyDownAt >= FRENZY_GRACE) and "MISSING" or nil
        addItem(items, self._frenzyIcon or 134400, 0, 0, label, true)
      end
    else
      self._frenzyDownAt = nil
    end

    -- LotP / Grace-of-Air positional states, combat-only like the reference:
    --   RANGE   — aura on a subgroup member but not on you (step back in)
    --   MISSING — no Grace anywhere in the subgroup, but a shaman is present
    -- Gated by reactBuffPositional (React HUD tab); off skips the whole group
    -- sweep too. ScanPlayer sets the on-me flags these read, so a flags-only
    -- pass runs first; the procs pass is the last thing into the row.
    self:ScanPlayer(true)
    if p.reactBuffPositional ~= false and state.player.inCombat then
      self:ScanGroup(GetTime())
      if not self._lotpOnMe and self._lotpInGroup and not dis.lotp then
        addItem(items, self._lotpIcon, 0, 0, "RANGE", true)
      end
      if not self._goaOnMe and not dis.grace then
        if self._goaInGroup then
          addItem(items, self._graceIcon, 0, 0, "RANGE", true)
        elseif self._shamanInSub then
          addItem(items, self._graceIcon, 0, 0, "MISSING", true)
        end
      end
    end

    -- Windfury: Nock's weapon-enchant detection, read straight off the
    -- TotemTracker engine's state (its view is hidden in React mode but the
    -- engine keeps publishing).
    local wf = state.totems and state.totems.windfury
    if wf and wf.present and not dis.windfury then
      addItem(items, wf.icon, wf.expirationTime, wf.duration)
    end

    self:ScanPet()
    self:ScanPlayer(false)
  end

  -- Lay out and repaint: icons centered, growing outward from the middle as
  -- more become active. Repositioning only runs when the count or the panel
  -- width changes.
  local slots = self._slots
  local n = items.n
  local w = self.frame:GetWidth() or 0
  if n ~= self._lastN or w ~= self._lastW then
    self._lastN, self._lastW = n, w
    local size, gap = REACT.ICON, REACT.GAP
    local totalW = n * size + (n - 1) * gap
    local x0 = (w - totalW) / 2
    for i = 1, n do
      local s = slots[i]
      s:ClearAllPoints()
      s:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", x0 + (i - 1) * (size + gap), 0)
    end
  end
  local now = GetTime()
  for i = 1, n do
    local s = slots[i]
    Nock.UI.PaintReactSlot(s, items[i], now)
    if not s:IsShown() then s:Show() end
  end
  for i = n + 1, MAX_ICONS do
    if slots[i]:IsShown() then slots[i]:Hide() end
  end
end
