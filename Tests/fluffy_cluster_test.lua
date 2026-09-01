-- Tests/fluffy_cluster_test.lua
-- Standalone LuaJIT tests for the FluffyHUD mode: the fluffy* defaults family
-- (§1), FluffyCluster:Geometry (§2, Task 1.2), and later the sub-bar painters
-- and CD-row membership. Harness modeled on buff_row_classic_test.lua.
-- Run from the repo root: luajit Tests/fluffy_cluster_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end

local Stub = dofile("Tests/lib/frame_stub.lua")
_G.CreateFrame = Stub.CreateFrame
_G.UIParent = Stub.CreateFrame("Frame")
_G.GetTime = function() return 1000 end
_G.unpack = unpack or table.unpack
_G.GetSpellInfo = function(id) return "Spell " .. id, nil, "icon-" .. id end
_G.GetRangedHaste = function() return 0 end

local Nock = { Constants = {}, state = {}, modules = {} }
function Nock:NewModule(name)
  local m = { name = name }
  function m:RegisterMessage() end
  function m:RegisterEvent() end
  function m:SendMessage() end
  Nock.modules[name] = m
  return m
end
function Nock:GetModule(name) return Nock.modules[name] end
function Nock.IsLocked() return true end
_G.LibStub = setmetatable({}, { __call = function(_, lib, silent)
  if lib == "AceAddon-3.0" then return { GetAddon = function() return Nock end } end
  if silent then return nil end
  return {}
end })

dofile("Core/Constants.lua")
dofile("Config/Defaults.lua")
dofile("Core/State.lua")

-- ---------------------------------------------------------------------------
-- §1 The fluffy* defaults family (Config/Defaults.lua). One entry per key the
-- spec names; a missing key or a drifted default fails by name.
-- ---------------------------------------------------------------------------
local D = Nock.Defaults.profile

local function eqColor(a, b)
  return type(a) == "table" and #a == #b
     and a[1] == b[1] and a[2] == b[2] and a[3] == b[3] and a[4] == b[4]
end

local NUMS = {
  fluffyWidth = 320, fluffyScale = 1.0, fluffyCastH = 14, fluffySwingH = 12,
  fluffyRangedH = 18, fluffyMeleeH = 8, fluffyRangeH = 12, fluffyShotWindow = 6.0,
  fluffyFontSize = 9,
}
for k, v in pairs(NUMS) do
  ok(D[k] == v, ("default %s == %s (got %s)"):format(k, tostring(v), tostring(D[k])))
end

local BOOLS = {
  fluffyShowCast = true, fluffyShowAutoShotCast = true, fluffyShowSwing = true,
  fluffyShowRanged = true, fluffyShowMelee = true, fluffyShowRange = true,
  fluffyShowGrid = false, fluffyBuffRows = true,
  fluffyBuffRowPos = false, fluffyCdKeys = false,
  fluffyShowNotation = true, fluffyShowDelay = false,
  fluffyShowBrackets = false, fluffyShowGcdDivider = false,
  fluffyShowClipTicks = true,
}
ok(D.fluffyDirAuto == "converge", "default fluffyDirAuto == converge")
for k, v in pairs(BOOLS) do
  ok(D[k] == v, ("default %s == %s (got %s)"):format(k, tostring(v), tostring(D[k])))
end

ok(D.fluffyBarTexture == "", "fluffyBarTexture sentinel \"\" (reference skin)")
ok(D.fluffyFont == "", "fluffyFont sentinel \"\" (reference skin)")
ok(type(D.fluffyCooldownDisabled) == "table" and next(D.fluffyCooldownDisabled) == nil,
   "fluffyCooldownDisabled == {}")

local COLORS = {
  fluffyColorCastFill   = { 0.40, 0.70, 1.00, 1.00 },
  fluffyColorSwingFill  = { 1.00, 0.84, 0.00, 1.00 },
  fluffyColorTickSteady = { 1.00, 0.10, 0.10, 1.00 },
  fluffyColorTickMulti  = { 1.00, 0.65, 0.10, 1.00 },
  fluffyColorTickWindup = { 0.85, 0.85, 0.85, 0.80 },
  fluffyColorGcdDivider = { 0.62, 0.35, 0.98, 1.00 },
  fluffyColorBracket    = { 1.00, 1.00, 1.00, 0.35 },
  fluffyColorSteady     = { 0.988, 0.596, 0.012, 0.85 },
  fluffyColorQueue      = { 0.988, 0.596, 0.012, 0.38 },
  fluffyColorQueueLive  = { 0.20, 0.90, 0.35, 0.90 },
  fluffyColorMulti      = { 0.012, 0.525, 0.996, 0.85 },
  fluffyColorArcane     = { 0.686, 0.478, 0.773, 0.85 },
  fluffyColorDanger     = { 0.851, 0.118, 0.118, 0.50 },
  fluffyColorRaptor     = { 0.153, 0.682, 0.376, 0.85 },
  fluffyColorWeaveAuto  = { 1.00, 1.00, 1.00, 0.70 },
  fluffyColorSpark      = { 1.00, 1.00, 1.00, 1.00 },
  fluffyColorRangeDeadzone = { 0.68, 0.18, 0.20, 1.00 },
  fluffyColorRangeSweet    = { 0.85, 0.66, 0.00, 1.00 },
  fluffyColorRangePerfect  = { 0.17, 0.78, 0.11, 1.00 },
  fluffyColorRangeClose    = { 0.00, 0.83, 0.75, 1.00 },
  fluffyColorRangeResync   = { 1.00, 0.58, 0.10, 1.00 },
}
for k, v in pairs(COLORS) do
  ok(eqColor(D[k], v), ("default %s color matches reference"):format(k))
end

-- ---------------------------------------------------------------------------
-- §2 FluffyCluster:Geometry — fixed order cast, swing, ranged, melee, range;
-- -1px seams between shown bars; the cast slot is RESERVED while enabled
-- (geometry never depends on whether a cast is running); a disabled sub-bar
-- costs zero height.
-- ---------------------------------------------------------------------------
Nock.db = { profile = {} }
for k, v in pairs(Nock.Defaults.profile) do Nock.db.profile[k] = v end
local p = Nock.db.profile

Nock.parentFrame = Stub.CreateFrame("Frame", "NockHUD", UIParent)
Nock.UI = {
  ApplyBackdrop      = function() end,
  PixelScale         = function() return 1 end,
  DeviceWidth        = function(n) return n end,
  PixelSnapCenter    = function(x) return x end,
  DelaySeverityColor = function() return 1, 1, 1 end,
  ReactAxisPoint     = function(frac, dir, halfW, innerW)
    if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
    if dir == "converge" then
      local d = 1 + frac * (halfW or 0)
      return "LEFT", d, true, d
    end
    return "LEFT", 1 + frac * (innerW or 0), false
  end,
  ReactGcdFrac       = function(gcd)
    if type(gcd) ~= "table" or not gcd.active then return nil end
    local dur = tonumber(gcd.duration)
    if not dur or dur <= 0 then return nil end
    local f = 1 - (tonumber(gcd.remaining) or 0) / dur
    if f < 0 then return 0 elseif f > 1 then return 1 end
    return f
  end,
}

dofile("UI/Frame_FluffyCluster.lua")
local FC = Nock.modules.FluffyCluster
FC:OnInitialize()

ok(FC.frame ~= nil, "cluster frame built")
ok(FC.frame:IsShown() == false, "cluster hidden at build (HUD shows it)")

local g = FC:Geometry()
ok(g.showRange == true, "range finder in the default stack, above the CD row")
ok(g.w == 320, "width = fluffyWidth")
ok(g.ySwing == 0 and g.hSwing == 12 and g.showSwing, "swing/cast bar at top, 12px")
ok(g.yRanged == 12 - 1, "ranged after the -1 seam")
ok(g.yMelee == 11 + 18 - 1, "melee after ranged")
ok(g.yRange == 28 + 8 - 1, "range after melee")
ok(g.total == 12 + 18 + 8 + 12 - 3, "total = heights minus 3 seams")
ok(FC:ContentHeight() == g.total, "ContentHeight == Geometry().total")

-- A running cast never changes geometry (the cast lives ON the swing bar).
Nock.state.player = { casting = { spellId = 1, startTime = 999, endTime = 1001 } }
local g2 = FC:Geometry()
ok(g2.total == g.total and g2.yRanged == g.yRanged, "cast running: geometry identical")
Nock.state.player.casting = nil

-- A middle bar off: the ones below move up.
p.fluffyShowMelee = false
g = FC:Geometry()
ok(g.showMelee == false, "melee off")
ok(g.yRange == 11 + 18 - 1, "range moves up past the missing melee lane")
ok(g.total == 12 + 18 + 12 - 2, "total without melee")
p.fluffyShowMelee = true

-- Height overrides go through the skin resolver.
p.fluffyRangedH = 24
g = FC:Geometry()
ok(g.hRanged == 24 and g.total == 12 + 24 + 8 + 12 - 3, "fluffyRangedH override honored")
p.fluffyRangedH = 18

-- ---------------------------------------------------------------------------
-- §3 The transient cast bar — a strip welded above the cluster, HIDDEN while
-- nothing casts (never a lane, never moves the stack). A cast fills, a
-- channel drains; the wind-up rides fluffyShowAutoShotCast; fluffyShowCast
-- is the master switch. GetTime() = 1000.
-- ---------------------------------------------------------------------------
Nock.state.player = {}
FC.frame:Show()

FC:Refresh(Nock.state)
ok(FC.castBar:IsShown() == false, "idle: the cast bar is hidden entirely")

Nock.state.player.casting = { name = "Steady Shot", icon = "ic",
                              startTime = 999.3, endTime = 1000.8 }
FC:Refresh(Nock.state)
ok(FC.castBar:IsShown() == true, "casting: the cast bar appears")
ok(FC.castBar.nameText:GetText() == "Steady Shot", "casting: name text")
ok(FC.castBar.timeText:GetText() == "0.8", "casting: remaining text, decisecond diffed")
-- elapsed 0.7 of 1.5 → 46.67% of innerW (320 - 2 = 318)
local wantW = (0.7 / 1.5) * 318
ok(math.abs(FC.castBar.fill._w - wantW) < 0.01, "casting: fill width = cast progress")

-- Channel drains instead of filling.
Nock.state.player.casting = { name = "Chan", isChannel = true,
                              startTime = 999.0, endTime = 1002.0 }
FC:Refresh(Nock.state)
local chanW = (1 - 1.0 / 3.0) * 318
ok(math.abs(FC.castBar.fill._w - chanW) < 0.01, "channel: fill drains (1 - elapsed/total)")

-- Cast gone → hidden again.
Nock.state.player.casting = nil
FC:Refresh(Nock.state)
ok(FC.castBar:IsShown() == false, "cast over: the bar hides")

-- Auto Shot wind-up as a cast: on by default, render-edge gated.
Nock.state.player.autoShotCast = { name = "Auto Shot",
                                   startTime = 999.8, endTime = 1000.3 }
FC:Refresh(Nock.state)
ok(FC.castBar:IsShown() == true and FC.castBar.nameText:GetText() == "Auto Shot",
   "wind-up shown as cast by default")
p.fluffyShowAutoShotCast = false
FC:Refresh(Nock.state)
ok(FC.castBar:IsShown() == false, "fluffyShowAutoShotCast off: wind-up not drawn")
p.fluffyShowAutoShotCast = true

-- The master switch hides the bar even mid-cast.
Nock.state.player.casting = { name = "Steady Shot",
                              startTime = 999.3, endTime = 1000.8 }
p.fluffyShowCast = false
FC:Refresh(Nock.state)
ok(FC.castBar:IsShown() == false, "fluffyShowCast off: no cast bar at all")
p.fluffyShowCast = true
Nock.state.player.casting = nil
Nock.state.player.autoShotCast = nil
FC:Refresh(Nock.state)

-- ---------------------------------------------------------------------------
-- §4 The React-style Auto Shot bar — converge fill via AutoSwingLive (two
-- halves meeting at the fire moment), mirrored breakpoint tick pairs
-- (Steady/Multi clip via Nock.ClipThreshold, wind-up commit), delay readout.
-- halfW = (320 - 2) / 2 = 159.
-- ---------------------------------------------------------------------------
Nock.state.ranged = { swingStart = 999, swingDuration = 2.0, swingRemaining = 1.0,
                      windup = 0.4, autoDelay = 0, repeating = true }
Nock.state.player.inCombat = true
FC:Refresh(Nock.state)
ok(math.abs(FC.swing.fillL._w - 0.5 * 159) < 0.01
   and math.abs(FC.swing.fillR._w - 0.5 * 159) < 0.01,
   "auto: both converge halves at the elapsed fraction of halfW")
local mp = FC.swing.windupL._point
ok(FC.swing.windupL._shown == true and mp and mp[1] == "CENTER"
   and math.abs(mp[4] - (1 + (1 - 0.4 / 2.0) * 159)) < 0.01,
   "auto: wind-up mark pair at 1 - windup/sd of halfW")
ok(FC.swing.windupR._shown == true, "auto: the mirrored wind-up mark too")
-- Clip ticks through the ONE shared threshold definition.
local sT = Nock.ClipThreshold(1.5)
if sT and sT > 0 and sT < 2.0 then
  local sp = FC.swing.steadyL._point
  ok(FC.swing.steadyL._shown == true and FC.swing.steadyR._shown == true
     and math.abs(sp[4] - (1 + ((2.0 - sT) / 2.0) * 159)) < 0.01,
     "auto: Steady clip tick pair at the shared threshold")
else
  ok(FC.swing.steadyL._shown == false, "auto: Steady tick hidden (threshold out of range)")
end

-- Held shot: expired swing stays full while fighting + auto still armed.
Nock.state.ranged.swingRemaining = -0.1
FC:Refresh(Nock.state)
ok(math.abs(FC.swing.fillL._w - 159) < 0.01, "auto: held shot stays full (repeating in combat)")

-- Disarmed (no swing recorded): empty, not solid gold.
Nock.state.ranged.swingStart = 0
FC:Refresh(Nock.state)
ok(FC.swing.fillL._w == 0.01, "auto: no live swing → empty fill")
Nock.state.ranged.swingStart = 999
Nock.state.ranged.swingRemaining = 1.0

-- The vertical marks are individually hideable: fluffyShowClipTicks owns the
-- Steady/Multi pairs, the SHARED showWindupMark owns the commit mark.
p.fluffyShowClipTicks = false
FC:ApplyLayout()
FC:Refresh(Nock.state)
ok(FC.swing.steadyL._shown == false and FC.swing.multiL._shown == false,
   "auto: fluffyShowClipTicks off hides the Steady/Multi ticks")
ok(FC.swing.windupL._shown == true, "auto: ...but not the wind-up mark")
p.showWindupMark = false
FC:ApplyLayout()
FC:Refresh(Nock.state)
ok(FC.swing.windupL._shown == false, "auto: shared showWindupMark off hides the commit mark")
p.fluffyShowClipTicks = true
p.showWindupMark = true
FC:ApplyLayout()
FC:Refresh(Nock.state)
ok(FC.swing.windupL._shown == true, "auto: marks return when re-enabled")

-- Rotation notation (fluffyShowNotation, default on): render-edge label off
-- state.rotation, Profiles-less fallback = the raw notation.
Nock.state.rotation = { notation = "1:1" }
FC:Refresh(Nock.state)
ok(FC.swing.notationText:GetText() == "1:1", "auto: notation label on the right edge")
p.fluffyShowNotation = false
FC:ApplyLayout()
FC:Refresh(Nock.state)
ok(FC.swing.notationText._shown == false and FC.swing.notationText:GetText() == "",
   "auto: fluffyShowNotation off hides and clears the label")
p.fluffyShowNotation = true
FC:ApplyLayout()

-- Delay readout is OPT-IN now (fluffyShowDelay, React parity).
Nock.state.ranged.autoDelay = 0.31
FC:Refresh(Nock.state)
ok(FC.swing.delayText._shown == false, "auto: delay readout hidden by default")
p.fluffyShowDelay = true
FC:ApplyLayout()
FC:Refresh(Nock.state)
ok(FC.swing.delayText:GetText() == "+0.31", "auto: delay readout formats when enabled + late")
Nock.state.ranged.autoDelay = 0
FC:Refresh(Nock.state)
ok(FC.swing.delayText:GetText() == "", "auto: delay readout empty when on time")
p.fluffyShowDelay = false
FC:ApplyLayout()

-- GCD divider (fluffyShowGcdDivider): the moving mark, converge pair.
Nock.state.gcd = { active = true, duration = 1.5, remaining = 0.75 }
FC:Refresh(Nock.state)
ok(FC.swing.gcdL._shown == false, "auto: GCD divider off by default")
p.fluffyShowGcdDivider = true
FC:ApplyLayout()
FC:Refresh(Nock.state)
local gp = FC.swing.gcdL._point
ok(FC.swing.gcdL._shown == true and FC.swing.gcdR._shown == true
   and gp and math.abs(gp[4] - (1 + 0.5 * 159)) < 0.01,
   "auto: GCD divider pair rides the GCD's progress")
Nock.state.gcd.active = false
FC:Refresh(Nock.state)
ok(FC.swing.gcdL._shown == false, "auto: divider gone once off the GCD")
p.fluffyShowGcdDivider = false
FC:ApplyLayout()
Nock.state.gcd = { remaining = 0 }

-- Fill direction: ltr = a single fill across the full inner width.
p.fluffyDirAuto = "ltr"
FC:ApplyLayout()
FC:Refresh(Nock.state)
ok(math.abs(FC.swing.fillL._w - 0.5 * 318) < 0.01, "auto: ltr single fill spans innerW")
ok(FC.swing.fillR._shown == false, "auto: ltr hides the mirrored half")
p.fluffyDirAuto = "converge"
FC:ApplyLayout()
FC:Refresh(Nock.state)

-- ---------------------------------------------------------------------------
-- §5 Range sub-bar painter — the shared view branch both existing range views
-- use: no target → dim empty; LONG → bracket block/drain per
-- rangeFinderFindingStyle; stale → RESYNC at 0.5; else zoom/linear fill.
-- ---------------------------------------------------------------------------
local Engine = dofile("Modules/RangeEngine.lua")
Nock.RangeEngine = Engine

Nock.state.target = {}
FC:Refresh(Nock.state)
ok(FC.range.fill._w == 0.01 and FC.range.label:GetText() == "",
   "range: no target → empty, no label")

-- Glide phase, linear fill: prog -0.5 → ratio 0.25.
Nock.state.target = { exists = true, alive = true, rangeState = "CLOSE", rangeProg = -0.5 }
FC:Refresh(Nock.state)
ok(math.abs(FC.range.fill._w - 0.25 * 318) < 0.01, "range: CLOSE fill = (prog+1)/2 of innerW")

-- Stale estimate parks at the tick with the RESYNC label.
Nock.state.target = { exists = true, alive = true, rangeState = "CLOSE",
                      rangeProg = 0, rangeEstimateStale = true }
FC:Refresh(Nock.state)
ok(FC.range.label:GetText() == "RESYNC", "range: stale → RESYNC label")
ok(math.abs(FC.range.fill._w - 0.5 * 318) < 0.01, "range: stale parks at 0.5")

-- LONG finding ladder: block style = full bracket fill + bracket label.
local bk, b = next(Engine.BRACKETS)
p.rangeFinderFindingStyle = "block"
Nock.state.target = { exists = true, alive = true, rangeState = "LONG", rangeBracket = bk }
FC:Refresh(Nock.state)
ok(FC.range.label:GetText() == b.label, "range: LONG block shows the bracket label")
ok(math.abs(FC.range.fill._w - 318) < 0.01, "range: LONG block fills solid")
p.rangeFinderFindingStyle = "drain"

-- Back to no target → cleared again.
Nock.state.target = {}
FC:Refresh(Nock.state)
ok(FC.range.fill._w == 0.01 and FC.range.label:GetText() == "",
   "range: target gone → cleared")

-- ---------------------------------------------------------------------------
-- §6 Shot lanes — pooled strips over the engine's span lists: ranged draw
-- order steady/queue/multi/arcane/danger clipped at the GCD/cast lockout,
-- melee weaveauto/raptor/weaveclip UNCLIPPED, full-height sparks, everything
-- hidden when the engine is idle. scale = innerW / windowSec = 318/6.
-- ---------------------------------------------------------------------------
local function shownStrips(pool)
  local n = 0
  for i = 1, #pool do if pool[i]._shown then n = n + 1 end end
  return n
end

Nock.state.gcd = { remaining = 0 }
Nock.state.player.casting = nil
Nock.state.shotpredict = {
  active = true, now = 1000, windowSec = 6,
  nSparks = 1, sparks = { 1002 },
  windows = {
    steady    = { n = 1, { s = 1000.5, e = 1002.0 } },
    queue     = { n = 1, { s = 999.9,  e = 1000.4 } },
    multi     = { n = 0 },
    arcane    = { n = 0 },
    danger    = { n = 1, { s = 1002.0, e = 1003.0 } },
    weaveauto = { n = 1, { s = 1000.2, e = 1001.0 } },
    raptor    = { n = 1, { s = 1001.0, e = 1002.0 } },
    weaveclip = { n = 0 },
  },
}
FC:Refresh(Nock.state)
local SC = 318 / 6
ok(shownStrips(FC.ranged.strips) == 3, "lanes: 3 ranged strips (steady, queue, danger)")
ok(shownStrips(FC.melee.strips) == 2, "lanes: 2 melee strips (weaveauto, raptor)")
-- Steady span pixels: x1 = floor(0.5*SC+.5), width = floor(2*SC+.5) - x1.
local st = FC.ranged.strips[1]
ok(st._point[4] == 1 + math.floor(0.5 * SC + 0.5), "lanes: steady left edge on the grid")
ok(st._w == math.floor(2 * SC + 0.5) - math.floor(0.5 * SC + 0.5), "lanes: steady width snapped")
-- Spark at +2s, full lane height.
ok(shownStrips(FC.ranged.sparks) == 1, "lanes: one spark shown")
ok(FC.ranged.sparks[1]._point[4] == 1 + math.floor(2 * SC + 0.5), "lanes: spark at +2s")

-- GCD lockout clips the ranged lane but never the melee lane.
Nock.state.gcd.remaining = 1.0
FC:Refresh(Nock.state)
local lockPx = math.floor(1.0 * SC + 0.5)
ok(FC.ranged.strips[1]._point[4] == 1 + lockPx, "lanes: ranged clipped at the lockout edge")
local mv = FC.melee.strips[1]
ok(mv._point[4] == 1 + math.floor(0.2 * SC + 0.5), "lanes: melee unclipped by the GCD")
Nock.state.gcd.remaining = 0

-- Spans fully inside the lockout disappear (steady and queue both end before
-- the 2.5s edge; only the danger band survives, clipped).
Nock.state.gcd.remaining = 2.5
FC:Refresh(Nock.state)
ok(shownStrips(FC.ranged.strips) == 1, "lanes: spans swallowed by the lockout are dropped")
Nock.state.gcd.remaining = 0

-- Engine idle → everything hidden.
Nock.state.shotpredict.active = false
FC:Refresh(Nock.state)
ok(shownStrips(FC.ranged.strips) == 0 and shownStrips(FC.melee.strips) == 0
   and shownStrips(FC.ranged.sparks) == 0, "lanes: idle engine → all strips hidden")
Nock.state.shotpredict.active = true

-- ---------------------------------------------------------------------------
-- §6b Lane spell icons (fluffyShowLaneIcons, default OFF) — each mapped span
-- gets its ability's icon centered in it, sized to the lane height; queue and
-- the danger/weaveclip bands NEVER carry one; a span too narrow for the icon
-- stays bare; idle engine hides them with the strips.
-- ---------------------------------------------------------------------------
ok(D.fluffyShowLaneIcons == false, "default fluffyShowLaneIcons == false")

_G.GetSpellTexture = function(id) return "tex-" .. id end

local function shownIcons(pool)
  local n = 0
  for i = 1, #(pool or {}) do if pool[i]._shown then n = n + 1 end end
  return n
end

Nock.state.shotpredict.windows.multi  = { n = 1, { s = 1002.0, e = 1003.5 } }
Nock.state.shotpredict.windows.arcane = { n = 1, { s = 1003.5, e = 1005.0 } }

-- Default off: no icons even with wide spans on every lane.
FC:Refresh(Nock.state)
ok(shownIcons(FC.ranged.icons) == 0 and shownIcons(FC.melee.icons) == 0,
   "icons: default off → none drawn")

p.fluffyShowLaneIcons = true
FC:Refresh(Nock.state)
-- Ranged: steady/multi/arcane get icons; queue and danger never do.
ok(shownIcons(FC.ranged.icons) == 3, "icons: steady+multi+arcane, never queue/danger")
ok(FC.ranged.icons[1]._tex == "tex-34120", "icons: steady wears Steady Shot")
ok(FC.ranged.icons[2]._tex == "tex-27021", "icons: multi wears Multi-Shot")
ok(FC.ranged.icons[3]._tex == "tex-27019", "icons: arcane wears Arcane Shot")
-- Melee: weaveauto wears the Attack fist, raptor wears Raptor Strike.
ok(shownIcons(FC.melee.icons) == 2, "icons: both melee spans carry one")
ok(FC.melee.icons[1]._tex == "tex-6603", "icons: weaveauto wears Attack")
ok(FC.melee.icons[2]._tex == "tex-27014", "icons: raptor wears Raptor Strike")
-- Left-aligned on the span's left edge, sized to the lane height (18 → 16).
local ix1 = math.floor(0.5 * SC + 0.5)
local isz = 18 - 2
ok(FC.ranged.icons[1]._w == isz and FC.ranged.icons[1]._h == isz,
   "icons: sized to the lane height")
ok(FC.ranged.icons[1]._point[4] == 1 + ix1, "icons: left-aligned in the span")

-- A span too narrow for the icon stays bare (steady shrunk under 16px).
Nock.state.shotpredict.windows.steady[1].e = 1000.7
FC:Refresh(Nock.state)
ok(shownIcons(FC.ranged.icons) == 2, "icons: too-narrow span stays bare")
Nock.state.shotpredict.windows.steady[1].e = 1002.0

-- Idle engine hides the icons with the strips.
Nock.state.shotpredict.active = false
FC:Refresh(Nock.state)
ok(shownIcons(FC.ranged.icons) == 0 and shownIcons(FC.melee.icons) == 0,
   "icons: idle engine → hidden")
Nock.state.shotpredict.active = true
p.fluffyShowLaneIcons = false
Nock.state.shotpredict.windows.multi  = { n = 0 }
Nock.state.shotpredict.windows.arcane = { n = 0 }

-- ---------------------------------------------------------------------------
-- §7 Fluffy CD row (UI/Frame_FluffyCooldowns.lua) — ONE stretch row seeded
-- with C.FLUFFY_CD_KEYS, membership via fluffyCdKeys override +
-- fluffyCooldownDisabled + Cooldowns:IsEntryAvailable; width split with -1px
-- seams over fluffyWidth.
-- ---------------------------------------------------------------------------
Nock.UI.CreateIconSlot = function(parent, name)
  local s = Stub.CreateFrame("Frame", name, parent)
  s.icon      = Stub.CreateFrame("Texture", nil, s)
  s.cooldown  = Stub.CreateFrame("Cooldown", nil, s)
  s.cdText    = Stub.CreateFrame("FontString", nil, s)
  s.countText = Stub.CreateFrame("FontString", nil, s)
  s.topText   = Stub.CreateFrame("FontString", nil, s)
  return s
end
Nock.UI.SetIconProcGlow  = function() end
Nock.UI.SetIconHighlight = function() end
Nock.UI.ApplyGlowStyle   = function() end
Nock.UI.ReactSlotLook    = function(cd, out, opts, res) res = res or {}; res.alpha = 1; return res end
Nock.UI.ReactLookKey     = function() return 1 end

local availability = {}
local cdmod = Nock:NewModule("Cooldowns")
function cdmod:GetEntry(key) return { key = key, icon = "icon-" .. key } end
function cdmod:IsEntryAvailable(key)
  if availability[key] == nil then return true end
  return availability[key]
end

ok(type(Nock.Constants.FLUFFY_CD_KEYS) == "table" and #Nock.Constants.FLUFFY_CD_KEYS == 6,
   "C.FLUFFY_CD_KEYS: the seeded six")
do
  -- Arcane/Multi stay OUT (drawn as windows in the shot lanes); the trinkets
  -- take their exact former positions.
  local want = { "KC", "T1", "T2", "Raptor", "Spec", "RF" }
  local same = true
  for i = 1, 6 do
    if Nock.Constants.FLUFFY_CD_KEYS[i] ~= want[i] then same = false end
  end
  ok(same, "seed = KC, Raptor, Spec, RF, T1, T2 (no Arc/MS)")
end

dofile("UI/Frame_FluffyCooldowns.lua")
local FCD = Nock.modules.FluffyCooldownsView
FCD:OnInitialize()
ok(FCD.frame ~= nil and FCD.frame:IsShown() == false, "CD row built hidden")
ok(FCD.frame:GetParent() == FC.frame,
   "CD row is the cluster's welded child (grows downward, no cascade height)")

local rows, w, h = FCD:RowsGeometry()
ok(#rows == 1 and w == 320 and h == 32, "one 32px row over fluffyWidth")
ok(#rows[1].entries == 6, "seeded six members")
ok(math.abs(rows[1].w - (320 + 5) / 6) < 0.001, "stretch: 6 tiles overlap 5 seams")
ok(FCD:ContentHeight() == 32, "ContentHeight = the row height")

p.fluffyCooldownDisabled = { Raptor = true }
rows = FCD:RowsGeometry()
ok(#rows[1].entries == 5, "a disabled key leaves the row")
p.fluffyCooldownDisabled = {}

availability.Spec = false
rows = FCD:RowsGeometry()
ok(#rows[1].entries == 5, "an unavailable entry (unknown spell) leaves the row")
availability.Spec = nil

p.fluffyCdKeys = { "KC", "RF" }
rows = FCD:RowsGeometry()
ok(#rows[1].entries == 2 and rows[1].entries[1].key == "KC" and rows[1].entries[2].key == "RF",
   "fluffyCdKeys override replaces the membership")
ok(math.abs(rows[1].w - (320 + 1) / 2) < 0.001, "stretch follows the member count")
p.fluffyCdKeys = false

-- Every member gone → the row collapses to nothing.
p.fluffyCdKeys = {}
local _, _, h0 = FCD:RowsGeometry()
ok(h0 == 1, "no members: height collapses (1px floor)")
p.fluffyCdKeys = false

-- ---------------------------------------------------------------------------
-- §8 Active-highlight styling plumb-through (per-HUD fluffyActive* keys):
-- Rebuild applies size/fit to every slot, Refresh hands the style to
-- ReactSlotLook and the profile color to SetIconHighlight.
-- ---------------------------------------------------------------------------
local seenStyle, seenColor = "unset", "unset"
Nock.UI.ReactSlotLook = function(cd, out, opts, res)
  seenStyle = opts.activeStyle
  res = res or {}
  res.vis, res.glow, res.alpha = "proc", "border", 1
  res.desat, res.tint = false, nil
  return res
end
local lookN = 0
Nock.UI.ReactLookKey = function() lookN = lookN + 1; return lookN end -- always repaint
Nock.UI.SetIconHighlight = function(_, color) seenColor = color end
local glowCalls = {}
Nock.UI.ApplyGlowStyle = function(_, size, contained)
  glowCalls[#glowCalls + 1] = { size = size, contained = contained }
end

p.fluffyActiveStyle = "glow"
p.fluffyActiveColor = { 1, 0, 0, 1 }
p.fluffyActiveSize  = 2
p.fluffyActiveFit   = "contained"
FCD:Rebuild()
ok(#glowCalls >= 6, "rebuild restyles every pooled slot's glow frame")
ok(glowCalls[1] and glowCalls[1].size == 2 and glowCalls[1].contained == true,
   "fluffyActiveSize/Fit reach ApplyGlowStyle")

FCD.frame:Show()
Nock.state.cooldowns = { KC = { procActive = true, icon = "icon-KC" } }
Nock.state.target = Nock.state.target or {}
FCD:Refresh(Nock.state)
ok(seenStyle == "glow", "fluffyActiveStyle reaches ReactSlotLook as opts.activeStyle")
ok(seenColor == p.fluffyActiveColor,
   "the border highlight is painted with fluffyActiveColor, not the hardcoded cyan")

p.fluffyActiveStyle, p.fluffyActiveColor = nil, nil
p.fluffyActiveSize, p.fluffyActiveFit = nil, nil

print(("fluffy_cluster: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
