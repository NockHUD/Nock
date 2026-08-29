-- Modules/RangeFinder.lua
-- Probes the target's range each tick and feeds two consumers: the LEGACY
-- zone classification (rangeZone/inMelee/meleeProximity — sounds, coach,
-- rotation gates) and the NEW two-mode display state (RangeEngine): a
-- finding ladder beyond ~10yd and a clamp-and-snap predictive weave bar
-- inside it (spec: docs/superpowers/specs/2026-08-06-rangefinder-finding-
-- glide-design.md).
--
-- PROBE DESIGN (written for raid robustness — KT/SSC/Hydross/Leotheras etc.):
-- Boss hitboxes are huge and CHANGE mid-fight (growth, model/phase shifts).
-- The ONLY distance signals that track that correctly are the in-engine range
-- checks, because they fold in the target's combat reach (bounding radius).
-- THREE reach-aware probes, each a different job:
--   • IsSpellInRange(Wing Clip)   → TRUE melee/auto-attack range (~5yd).
--     This is "am I in melee" — NOT the 7yd item (it over-reports ~2yd early).
--   • IsItemInRange(8149)         → ~7yd "within one weave-step of melee".
--     Defines the weave-ready / sweet band (the WA's exact probe). Falls back
--     to the melee probe if the item API is unavailable.
--   • IsSpellInRange(Auto Shot)   → ranged usable band (past the ~5yd min).
-- Why three: with Wing Clip (~5yd) AND Auto Shot's ~5yd minimum, you can
-- almost never BOTH melee and shoot — so a literal melee&&shoot "sweet" state
-- basically never fires. The real weave sweet spot is being just OUTSIDE
-- melee but within a step (inside 8149's ~7yd) while still able to shoot.
-- That band is "PERFECT". No CheckInteractDistance (center-based, NOT
-- reach-aware → the old "stuck on bosses" bug) and no speed dead-reckoning.
-- Brief nils during shape/phase transitions are held for a short grace, then
-- the whole state is frozen (not snapped to OUT) until the probes report
-- again. The bar position is a band-derived target the thumb EASES toward.
--
-- Zones (state.target.rangeZone) and the label the view shows:
--   SWEET     : in melee AND can shoot (rare overlap)        → "IN MELEE"
--   TOO_CLOSE : in melee can't shoot, or the dead gap         → "DEAD ZONE"
--   TOO_FAR   : can shoot; far (rest) → "TOO FAR", within the
--               7yd weave ring → "PERFECT" (the spot to be in)
--   OUT       : can't shoot, not near melee — far / no line   → "OUT"

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local RangeFinder = Nock:NewModule("RangeFinder", "AceEvent-3.0")
local C = Nock.Constants

-- Voodoo Charm: IsItemInRange ≈ 7yd and combat-reach aware — the inspiration
-- WA's exact "within a weave-step of melee" probe. Used ONLY for the weave
-- ring, never for the in-melee flag. API form varies; resolve once.
local MELEE_ITEM  = 8149
local ItemInRange = IsItemInRange or (C_Item and C_Item.IsItemInRange)

-- ~10yd close probe (WA "inCloseRange", item 17626): defines the finding ->
-- glide handoff. Same reach-aware IsItemInRange family as 8149.
local CLOSE_ITEM = 17626

-- Candidate range-probe items for /nock range (LibRangeCheck-community IDs,
-- long-stable across Classic/TBC). NOMINAL yards shown; the client inflates
-- effective range by the target's combat reach (8149 nominal 5 → ~7 here), so
-- two "5yd" items can resolve differently. Hunting one that flips between the
-- perfect-rest spot and the just-too-far spot to use as a tighter weave ring.
local PROBE_ITEMS = {
  { 21519, "Mistletoe~4"   },
  { 8149,  "Voodoo~5"      },
  { 33069, "SturdyRope~15?" },
  { 17626, "FrostwolfMuzzle~10?" },
  { 10645, "GnomishDeathRay~20?" },
  { 18904, "Shrinker~35?"  },
  { 34191, "HnRope~5"      },
  { 24268, "NWNet~15"      },
  { 7734,  "SixDemonBag~30?" },
  { 4945,  "FaintlyGlowingSkull~40?" },
  { 13289, "Egan~25?"      },
}

-- Hold a probe's last good value this long when it momentarily returns nil
-- (common right on a phase/model swap). Past this with no valid probe at all
-- we FREEZE the displayed state (never snap to OUT) until LOST.
local GRACE = 0.5
local LOST  = 2.0

-- Bar anchor positions, in the view's clamp space (-0.15..0.15, 0 = melee
-- threshold). The view shows "PERFECT" only for zone TOO_FAR with prox in
-- [-0.05,0] and "CLOSE" in [-0.10,-0.05). Live diagnosis (Servant of
-- Razelikh) proved Wing Clip's IsSpellInRange is the only probe that matches
-- "can I actually land a melee" (it read 0 where a weave would not connect,
-- while Raptor-Strike-range and the 7yd item both falsely read in-range). So
-- PERFECT is gated on Wing Clip (true melee); the 7yd item only powers the
-- softer "CLOSE" approach hint and can never show PERFECT.
local P_OUT     = -0.15
local P_FAR     = -0.12   -- can shoot, too far to step-weave → "TOO FAR"
local P_WEAVE   = -0.02   -- REST/LAUNCH spot: can shoot, ~1 step from melee → "PERFECT"
                          -- (sits inside the view's narrowed PERFECT band [-0.025, 0])
local P_SWEET   = -0.02   -- in melee AND can shoot (rare) → "IN MELEE"
local P_GAP     =  0.06   -- near but neither shoot nor melee (dead gap)
local P_DEEP    =  0.10   -- in melee, can't shoot → "DEAD ZONE" (strike & step back)

-- Practice mode publishes target.meleeProximity / target.rangeZone through
-- these two maps (Modules/Practice.lua), so the simulated zone and the live
-- classifier can never disagree: the bar, the coach and the rotation engine all
-- read the same anchors whether the zone came from a probe or from the sim.
-- Keys are PracticeEngine's fine-grained zone names (zoneOf).
RangeFinder.PROX = {
  OUT = P_OUT, FAR = P_FAR, WEAVE = P_WEAVE, SWEET = P_SWEET, GAP = P_GAP, DEEP = P_DEEP,
}
RangeFinder.LEGACY = {
  OUT = "OUT", FAR = "TOO_FAR", WEAVE = "TOO_FAR", SWEET = "SWEET",
  GAP = "TOO_CLOSE", DEEP = "TOO_CLOSE",
}

local function spellName(spellID)
  if GetSpellInfo then
    local n = GetSpellInfo(spellID)
    if n then return n end
  end
  if C_Spell and C_Spell.GetSpellInfo then
    local i = C_Spell.GetSpellInfo(spellID)
    if i then return i.name end
  end
  return nil
end

-- Normalise the various range-API return shapes (1/0, true/false, nil) to a
-- strict tri-state: true / false / nil(unknown).
local function tri(v)
  if v == 1 or v == true  then return true  end
  if v == 0 or v == false then return false end
  return nil
end

-- "Can I actually melee/weave right now?" = Wing Clip in range. Wing Clip is
-- a melee ability, so IsSpellInRange tracks TRUE melee/auto-attack range
-- (~5yd) and is combat-reach aware (correct on huge boss hitboxes). Never
-- CheckInteractDistance (center-based, lies about big hitboxes) and not the
-- ~7yd item probe (over-reports in-melee ~2yd early).
local function meleeProbe(self)
  if IsSpellInRange and self.wingClipName then
    local r = tri(IsSpellInRange(self.wingClipName, "target"))
    if r ~= nil then return r end
  end
  if C_Spell and C_Spell.IsSpellInRange then
    local r = tri(C_Spell.IsSpellInRange(C.SpellID.WING_CLIP, "target"))
    if r ~= nil then return r end
  end
  return nil
end

-- "Within one weave-step of melee?" = inside ~7yd (item 8149), reach-aware.
-- If the item API isn't available, degrade to the melee probe (so the weave
-- ring just collapses onto melee rather than breaking).
local function nearProbe(self)
  if ItemInRange then
    local r = tri(ItemInRange(MELEE_ITEM, "target"))
    if r ~= nil then return r end
  end
  return meleeProbe(self)
end

-- "Inside ~10yd?" — the finding->glide handoff boundary (item 17626).
-- Degrades to the near probe if the item API is missing (handoff collapses
-- onto the 7yd ring rather than breaking).
local function closeProbe(self)
  if ItemInRange then
    local r = tri(ItemInRange(CLOSE_ITEM, "target"))
    if r ~= nil then return r end
  end
  return nearProbe(self)
end

-- Combat-reach-aware "can I Auto Shot?" (== inside the min..max usable band).
local function shootProbe(self)
  if IsSpellInRange and self.autoShotName then
    local r = tri(IsSpellInRange(self.autoShotName, "target"))
    if r ~= nil then return r end
  end
  if C_Spell and C_Spell.IsSpellInRange then
    local r = tri(C_Spell.IsSpellInRange(C.SpellID.AUTO_SHOT, "target"))
    if r ~= nil then return r end
  end
  return nil
end

-- Return the probe value, holding the last good one through brief nils.
local function withGrace(self, field, raw, now)
  if raw ~= nil then
    self[field], self[field .. "At"] = raw, now
    return raw
  end
  local last, at = self[field], self[field .. "At"] or 0
  if last ~= nil and (now - at) <= GRACE then return last end
  return nil
end

local function clearTarget(self, t)
  t.exists, t.alive, t.friendly, t.rangeZone = false, false, false, nil
  t.inMelee, t.meleeProximity = false, 0
  t.rangeState, t.rangeProg, t.rangeBracket = nil, -1, nil
  self._prog = 0
  self._melee, self._near, self._shoot = nil, nil, nil
  self._meleeAt, self._nearAt, self._shootAt = 0, 0, 0
  self._close, self._closeAt = nil, 0
  self._zone, self._inMelee = nil, false
  self._lastKnown = 0
  t.rangeEstimateStale = false
  if self._eng then Nock.RangeEngine.Reset(self._eng) end
  self._bracket, self._ladderAt = nil, 0
end

function RangeFinder:OnEnable()
  self.autoShotName  = spellName(C.SpellID.AUTO_SHOT) or "Auto Shot"
  self.wingClipName  = spellName(C.SpellID.WING_CLIP) or "Wing Clip"
  self._prog         = 0
  self._lastFrame    = GetTime()
  self._lastKnown    = 0
  self._eng = Nock.RangeEngine.New()
  self._lr  = {}          -- reusable ladder probe table (no per-tick allocs)
  self._ladderAt = 0
  self._bracket = nil
  self:RegisterEvent("PLAYER_LOGIN")
  self:RegisterEvent("PLAYER_TARGET_CHANGED")
  -- New-spell-learned recompile: the Anniversary client REMOVED
  -- LEARNED_SPELL_IN_TAB (modern name: LEARNED_SPELL_IN_SKILL_LINE), and
  -- AceEvent hard-errors on unknown events. Try the precise names, fall back
  -- to the broad SPELLS_CHANGED — CompileLadder is cheap either way.
  if not (pcall(self.RegisterEvent, self, "LEARNED_SPELL_IN_SKILL_LINE", "CompileLadder")
          or pcall(self.RegisterEvent, self, "LEARNED_SPELL_IN_TAB", "CompileLadder")) then
    self:RegisterEvent("SPELLS_CHANGED", "CompileLadder")
  end
  self:RegisterEvent("CHARACTER_POINTS_CHANGED", "CompileLadder")
  self:CompileLadder()
end

function RangeFinder:PLAYER_LOGIN()
  self.autoShotName = spellName(C.SpellID.AUTO_SHOT) or self.autoShotName
  self.wingClipName = spellName(C.SpellID.WING_CLIP) or self.wingClipName
  self:CompileLadder()
end

function RangeFinder:PLAYER_TARGET_CHANGED()
  if Nock.state.sim.active then return end   -- practice mode publishes target.*
  if not UnitExists("target") then
    clearTarget(self, Nock.state.target)
  else
    -- New target: drop stale probe history so we don't inherit the last
    -- target's melee state for a frame.
    self._melee, self._near, self._shoot = nil, nil, nil
    self._meleeAt, self._nearAt, self._shootAt = 0, 0, 0
    self._close, self._closeAt = nil, 0
    self._zone, self._inMelee = nil, false
    self._lastKnown = 0
    if self._eng then Nock.RangeEngine.Reset(self._eng) end
    self._bracket, self._ladderAt = nil, 0
  end
end

-- Resolve talent/spell-dependent ladder inputs. Cheap; runs at login and on
-- talent events only. GetTalentInfo(3, 23) = Hawk Eye (VERIFY in-game on
-- Anniversary — part of the calibration session).
function RangeFinder:CompileLadder()
  local rank = 0
  if GetTalentInfo then
    rank = select(5, GetTalentInfo(3, 23)) or 0
  end
  self._hawkEye = rank

  self.scatterName = spellName(C.SpellID.SCATTER_SHOT)
  self._scatterKnown = false
  if IsSpellKnown then
    self._scatterKnown = IsSpellKnown(C.SpellID.SCATTER_SHOT) == true
  elseif IsPlayerSpell then
    self._scatterKnown = IsPlayerSpell(C.SpellID.SCATTER_SHOT) == true
  end

  -- Highest known Hunter's Mark rank (WA rank ladder + the TBC top rank).
  self.hmName = nil
  local hmRanks = { 27322, 14325, 14324, 14323, 1130 }
  for i = 1, #hmRanks do
    local known = (IsSpellKnown and IsSpellKnown(hmRanks[i]))
      or (IsPlayerSpell and IsPlayerSpell(hmRanks[i]))
    if known then
      self.hmName = spellName(hmRanks[i])
      break
    end
  end
end

-- Finding-mode ladder scan, throttled. Fills the reusable self._lr table and
-- resolves the bracket key. nil probe reads count as false (WA behavior) —
-- at 100ms cadence and 5yd-wide brackets, grace holds aren't worth the state.
local LADDER_SCAN = 0.1
function RangeFinder:ScanLadder(now, shoot)
  if (now - self._ladderAt) < LADDER_SCAN then return end
  self._ladderAt = now
  local r = self._lr
  if ItemInRange then
    r.i13289 = tri(ItemInRange(13289, "target")) == true
    r.i33069 = tri(ItemInRange(33069, "target")) == true
    r.i10645 = tri(ItemInRange(10645, "target")) == true
    r.i18904 = tri(ItemInRange(18904, "target")) == true
    r.i7734  = tri(ItemInRange(7734,  "target")) == true
    r.i4945  = tri(ItemInRange(4945,  "target")) == true
  else
    r.i13289, r.i33069, r.i10645, r.i18904, r.i7734, r.i4945 =
      false, false, false, false, false, false
  end
  r.autoShot = (shoot == true)
  r.scatter = false
  if self._scatterKnown and IsSpellInRange and self.scatterName then
    r.scatter = tri(IsSpellInRange(self.scatterName, "target")) == true
  end
  r.hm = nil
  if self.hmName and IsSpellInRange then
    r.hm = tri(IsSpellInRange(self.hmName, "target")) == true
  end
  self._bracket = Nock.RangeEngine.ResolveBracket(
    r, self._hawkEye or 0, self._scatterKnown, self.hmName ~= nil)
end

-- Exposed for /nock debug — lets the user read the raw probes on a real boss.
function RangeFinder:DebugProbes()
  return ("rangefinder: melee=%s near=%s shoot=%s zone=%s prox=%.2f"):format(
    tostring(self._melee), tostring(self._near), tostring(self._shoot),
    tostring(self._zone), self._prog or 0)
end

-- Route a text block into BugSack (via BugGrabber's error handler — the
-- standard way to inject copyable text) as ONE entry. Only when BugGrabber is
-- actually loaded, so we never pop the default Lua error frame otherwise.
local function toBugSack(text)
  local present = _G.BugGrabber
  if not present then
    local chk = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if chk then
      present = chk("!BugGrabber") or chk("BugGrabber") or chk("BugSack")
    end
  end
  if present and geterrorhandler then
    local eh = geterrorhandler()
    if eh then return pcall(eh, text) end
  end
  return false
end

-- Accumulating copy window — the reliable "easy copy pasta" path. BugGrabber
-- groups/dedups repeated injected messages (it strips numbers when grouping)
-- and tacks on a traceback, so distinct samples collapse into one confusing
-- entry. This frame just shows every snapshot verbatim, select-all ready.
local copyFrame
local function showCopyBox(text)
  if not copyFrame then
    local f = CreateFrame("Frame", "NockRangeCopy", UIParent, "BackdropTemplate")
    f:SetSize(580, 360)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    Nock.UI.ApplyBackdrop(f)

    local sf = CreateFrame("ScrollFrame", "NockRangeCopyScroll", f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 14, -14)
    sf:SetPoint("BOTTOMRIGHT", -34, 44)
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFontObject(_G.ChatFontNormal or _G.GameFontHighlightSmall)
    eb:SetWidth(520)
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    sf:SetScrollChild(eb)
    f.eb = eb

    local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    close:SetSize(90, 22)
    close:SetPoint("BOTTOMRIGHT", -14, 12)
    close:SetText("Close")
    close:SetScript("OnClick", function() f:Hide() end)

    local clr = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    clr:SetSize(90, 22)
    clr:SetPoint("BOTTOMLEFT", 14, 12)
    clr:SetText("Clear")
    clr:SetScript("OnClick", function()
      RangeFinder._rangeBuf = {}
      f.eb:SetText("")
    end)

    copyFrame = f
  end
  copyFrame.eb:SetText(text)
  -- Size the editbox to the content so the scroll frame can scroll it.
  local _, nl = tostring(text):gsub("\n", "\n")
  copyFrame.eb:SetHeight(math.max(300, (nl + 2) * 14))
  copyFrame:Show()
  copyFrame.eb:SetFocus()
  copyFrame.eb:HighlightText()
  copyFrame.eb:SetCursorPosition(0)
end

-- /nock range — RAW snapshot of every range probe for the current target.
-- Values are 1/0/nil exactly (un-graced) so nil (unknown) is distinct from 0
-- (out of range). Each run APPENDS to the copy window (and best-effort to
-- BugSack). Run it at the "PERFECT but can't weave" spot and at the spot a
-- weave just connects — note your ground truth (did a melee land) per sample.
function RangeFinder:Diagnose()
  if not UnitExists("target") then
    Nock:Print("range: no target"); return
  end
  -- Raw spell-in-range, name form first then C_Spell(id).
  local function ssir(id, nm)
    local v
    if IsSpellInRange and nm then v = IsSpellInRange(nm, "target") end
    if v == nil and C_Spell and C_Spell.IsSpellInRange then
      v = C_Spell.IsSpellInRange(id, "target")
    end
    return tostring(v)
  end
  local item8149 = "n/a"
  if ItemInRange then item8149 = tostring(ItemInRange(MELEE_ITEM, "target")) end
  local cid = {}
  for i = 1, 4 do
    cid[i] = (CheckInteractDistance and CheckInteractDistance("target", i)) and "1" or "0"
  end
  local uir = "n/a"
  if UnitInRange then uir = UnitInRange("target") and "1" or "0" end

  -- Item-probe ladder: which (if any) flips between the perfect-rest spot and
  -- the just-too-far spot → that's the tighter weave-ring probe to adopt.
  local ladder = {}
  for _, it in ipairs(PROBE_ITEMS) do
    local v = "n/a"
    if ItemInRange then v = tostring(ItemInRange(it[1], "target")) end
    ladder[#ladder + 1] = it[2] .. "=" .. v
  end

  self._rangeDiagN = (self._rangeDiagN or 0) + 1
  local stamp = (date and date("%H:%M:%S")) or tostring(GetTime())
  local lines = {
    ("Nock /nock range #%d @%s"):format(self._rangeDiagN, stamp),
    ("  tgt=%s cls=%s lvl=%s"):format(
      tostring(UnitName("target")),
      tostring(UnitClassification and UnitClassification("target")),
      tostring(UnitLevel and UnitLevel("target"))),
    ("  WingClip(melee~5)=%s  Raptor(melee)=%s  AutoShot=%s"):format(
      ssir(C.SpellID.WING_CLIP, self.wingClipName),
      ssir(C.SpellID.RAPTOR_STRIKE, spellName(C.SpellID.RAPTOR_STRIKE)),
      ssir(C.SpellID.AUTO_SHOT, self.autoShotName)),
    ("  item8149(~7)=%s  CID 1/2/3/4=%s/%s/%s/%s  UnitInRange(~40)=%s"):format(
      item8149, cid[1], cid[2], cid[3], cid[4], uir),
    ("  itemladder: %s"):format(table.concat(ladder, " ")),
    ("  -> zone=%s prox=%.3f  graced m/n/s/c=%s/%s/%s/%s"):format(
      tostring(self._zone), self._prog or 0,
      tostring(self._melee), tostring(self._near), tostring(self._shoot),
      tostring(self._close)),
    ("  ladder: hawkEye=%s scatter=%s(%s) hm=%s(%s) bracket=%s state=%s prog=%.3f"):format(
      tostring(self._hawkEye),
      tostring(self._scatterKnown),
      self.scatterName and (IsSpellInRange and tostring(IsSpellInRange(self.scatterName, "target")) or "?") or "-",
      tostring(self.hmName),
      self.hmName and (IsSpellInRange and tostring(IsSpellInRange(self.hmName, "target")) or "?") or "-",
      tostring(self._bracket), tostring(self._eng and self._eng.state),
      (self._eng and self._eng.prog) or -1),
  }
  local block = table.concat(lines, "\n")

  -- Accumulate every distinct sample in the copy window (the reliable path).
  self._rangeBuf = self._rangeBuf or {}
  self._rangeBuf[#self._rangeBuf + 1] = block
  showCopyBox(table.concat(self._rangeBuf, "\n\n"))

  -- Best-effort BugSack too (honoured request) — but it dedups, so the copy
  -- window is the source of truth for multiple samples.
  toBugSack(block)

  Nock:Print(("range #%d captured -> copy window (Ctrl+C) | zone=%s WingClip=%s item8149=%s"):format(
    self._rangeDiagN, tostring(self._zone),
    ssir(C.SpellID.WING_CLIP, self.wingClipName), item8149))
end

function RangeFinder:Refresh(state)
  if Nock.state.sim.active then return end   -- practice mode publishes target.*
  local t = state.target
  local now = GetTime()
  local delta = math.max(0, now - (self._lastFrame or now))
  self._lastFrame = now

  if not UnitExists("target") then
    clearTarget(self, t)
    return
  end

  t.exists   = true
  t.alive    = not UnitIsDead("target")
  t.friendly = not UnitCanAttack("player", "target")

  if not t.alive or t.friendly then
    t.rangeZone = nil
    t.inMelee, t.meleeProximity = false, 0
    t.rangeState, t.rangeProg, t.rangeBracket = nil, -1, nil
    t.rangeEstimateStale = false
    self._prog = 0
    self._zone, self._inMelee = nil, false
    return
  end

  local melee = withGrace(self, "_melee", meleeProbe(self), now)
  local near  = withGrace(self, "_near",  nearProbe(self),  now)
  local shoot = withGrace(self, "_shoot", shootProbe(self), now)
  local close = withGrace(self, "_close", closeProbe(self), now)

  local zone, target, inMelee

  if melee == nil and near == nil and shoot == nil then
    -- Total probe blackout (usually a phase/model swap). Hold the last known
    -- state briefly rather than lying with OUT; only give up after LOST so a
    -- genuinely gone target still resolves.
    if (now - (self._lastKnown or 0)) > LOST then
      zone, target, inMelee = "OUT", P_OUT, false
    else
      zone, target, inMelee = self._zone or "OUT", self._prog, self._inMelee or false
    end
  else
    self._lastKnown = now
    local m  = (melee == true)   -- Wing Clip: in TRUE melee (can't auto-shoot here)
    local sh = (shoot == true)   -- Auto Shot usable
    local nr = (near == true)    -- 8149 ~7yd: within ~one weave step of melee
    -- The weave loop the user described: REST at the spot where you can shoot
    -- AND are ~1 step from melee ("PERFECT"); step in → briefly in melee, can't
    -- shoot ("DEAD ZONE") → Raptor → step back out. So in-melee is the dead
    -- zone (don't linger), and the shoot-capable ring just outside it is the
    -- good resting spot. Validated against live Servant-of-Razelikh samples.
    if m and sh then
      zone, target, inMelee = "SWEET", P_SWEET, true       -- in melee AND can shoot (rare/ideal)
    elseif m then
      zone, target, inMelee = "TOO_CLOSE", P_DEEP, true    -- in melee, no shoot → "DEAD ZONE"
    elseif sh and nr then
      zone, target, inMelee = "TOO_FAR", P_WEAVE, false    -- rest/launch spot → "PERFECT"
    elseif sh then
      zone, target, inMelee = "TOO_FAR", P_FAR, false      -- can shoot, too far to step-weave → "TOO FAR"
    elseif nr then
      zone, target, inMelee = "TOO_CLOSE", P_GAP, false    -- dead gap: near, no shoot, no melee
    else
      zone, target, inMelee = "OUT", P_OUT, false
    end
  end

  self._zone, self._inMelee = zone, inMelee

  -- Legacy anchor publication: instant P_* values (no easing — no display
  -- consumer left; Rotation/Core band checks behave as before).
  self._prog = target

  -- Predictive engine (display truth): WA state machine + clamp-and-snap.
  -- Gated on at least one probe being known: during a total probe blackout
  -- (phase/model swap) the engine HOLDS its last state instead of misreading
  -- "everything false" as LONG and flashing the finding ladder — the engine
  -- counterpart of the legacy zone-freeze above.
  local eng = self._eng
  if melee ~= nil or near ~= nil or shoot ~= nil or close ~= nil then
    local speed  = (GetUnitSpeed and GetUnitSpeed("player")) or 0
    local tspeed = (GetUnitSpeed and GetUnitSpeed("target")) or 0
    Nock.RangeEngine.Step(eng,
      close == true, near == true, melee == true, speed, tspeed, delta)
  end

  if eng.state == "LONG" then
    self:ScanLadder(now, shoot)
    t.rangeBracket = self._bracket
  else
    t.rangeBracket = nil
  end

  t.rangeState         = eng.state
  t.rangeProg          = eng.prog
  t.rangeEstimateStale = eng.resync
  t.rangeZone          = zone
  t.inMelee            = inMelee
  t.meleeProximity     = self._prog
end
