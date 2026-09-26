-- Tests/forever_aura_row_test.lua
-- Forever/AuraRow.lua: Blizzard's aura container as the client-drawn half of
-- the Forever buff row (short own buffs, procs included), styled like the
-- HUD's tiles and anchored after the ledger tiles.
-- Run from the repo root: luajit Tests/forever_aura_row_test.lua

local pass, fail = 0, 0
local function ok(c, n) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. n) end end

local sized = {}
local Nock = { UI = { SetReactSlotSize = function(b, size) sized[#sized + 1] = { b, size }; b:SetSize(size, size) end } }
_G.LibStub = function() return { GetAddon = function() return Nock end } end
_G.AnchorUtil = { FlowLayoutAxis = { Horizontal = 0, Vertical = 1 }, FlowDirection = { Down = -1, Left = -1, Right = 1, Up = 1 } }
_G.AuraContainerSortMethod = { Default = 0, Expiration = 4 }
_G.AuraContainerSortDirection = { Normal = 0, Reverse = 1 }

-- Fakes: a container that records its configuration, a button that records
-- the regions it is handed.
local function region()
  local r = { points = {}, SetAllPoints = function() end, SetColorTexture = function() end, SetTexCoord = function() end }
  function r:SetPoint(p) self.points[#self.points + 1] = p end
  function r:SetJustifyH(j) self.jh = j end
  function r:SetJustifyV(j) self.jv = j end
  return r
end
local Btn = {}
Btn.__index = Btn
function Btn:CreateTexture() return region() end
function Btn:CreateFontString() return region() end
function Btn:SetSize(w, h) self.w, self.h = w, h end
function Btn:SetIcon(t) self.iconSet = t end
function Btn:SetDurationText(fs, options) self.durationText = fs; self.durationOptions = options end
function Btn:IsShown() error("secret boolean") end

local Cont = {}
Cont.__index = Cont
function Cont:SetUnit(u) self.unit = u end
function Cont:SetFlowLayoutAxis(a) self.axis = a end
function Cont:SetFlowLayoutGrowthDirection(h, v) self.grow = { h, v } end
function Cont:SetFlowLayoutAnchorPoint(p) self.anchor = p end
function Cont:AddAuraGroup(k, f, o)
  self.groups = self.groups or {}
  self.order = self.order or {}
  self.groups[k] = { key = k, filter = f, opts = o, buttons = {} }
  self.order[#self.order + 1] = k
  self.group = self.group or self.groups[k]   -- the first group: the short row
  self.buttons = self.buttons or self.groups[k].buttons
  for i = 1, 2 do self.groups[k].buttons[i] = setmetatable({}, Btn); o.initializeFrame(self.groups[k].buttons[i]) end
end
function Cont:GetAuraGroupFrame(k, i) local g = self.groups and self.groups[k]; return g and g.buttons[i] or nil end
function Cont:SetAuraGroupCandidateFilters(k, f) self.refiltered = self.refiltered or {}; self.refiltered[k] = f end
function Cont:UpdateAllAuras() self.reread = (self.reread or 0) + 1 end
function Cont:SetEnabled(e) self.enabled = e end
function Cont:Show() self.shown = true end
function Cont:Hide() self.shown = false end
function Cont:ClearAllPoints() self.points = {} end
function Cont:SetPoint(p, rel, rp, x, y) self.points[#self.points + 1] = { p, rel, rp, x, y } end

local created = {}
_G.CreateFrame = function(kind, name, parent, template)
  local c = setmetatable({ kind = kind, name = name, parent = parent, template = template }, Cont)
  created[#created + 1] = c
  return c
end

dofile("Forever/AuraRow.lua")
local R = Nock.ForeverAuraRow
ok(R and R.MAX_DURATION == 60 and R.MAX_FRAMES == 8, "module with the short-buff cap")

local panel = { name = "panel" }
local c = R.Create(panel, 26, -1)
ok(c and c.kind == "AuraContainer" and c.template == "CustomAuraContainerTemplate" and c.parent == panel, "container created on the row's panel")
ok(c.unit == "player" and c.axis == 0 and c.grow[1] == 1 and c.grow[2] == -1 and c.anchor == "BOTTOMLEFT", "player, horizontal, growing right from the bottom-left")
ok(c.group.filter == "HELPFUL|PLAYER" and c.group.opts.maxFrameCount == 8, "own helpful auras, eight at most")
ok(c.group.opts.candidateFilters.maxDuration == 60, "short buffs only: the duration cap")
ok(c.group.opts.sortMethod == 4 and c.group.opts.sortDirection == 0, "sorted by expiration, soonest first (like the ledger)")
ok(c.group.opts.layout.elementWidth == 26 and c.group.opts.layout.elementHeight == 26 and c.group.opts.layout.elementSpacing == -1, "tile-sized elements with the row's seam overlap")
ok(c.enabled == true and c.shown == true, "enabled and shown")

-- Buttons: styled once through the hook, in the tile look.
local b = c.buttons[1]
ok(b.iconSet ~= nil and b.durationText ~= nil, "a button is handed an icon texture and a countdown font string")
ok(b.time ~= nil and b.label ~= nil and b.w == 26, "time/label font strings sized through SetReactSlotSize")
local before = #sized
R.Style(b, 26)
ok(#sized == before, "styling is idempotent")

-- The container is centred by the client (anchored bottom-centre), once.
R.Anchor(c, panel)
ok(#c.points == 1 and c.points[1][1] == "BOTTOM" and c.points[1][3] == "BOTTOM" and c.points[1][4] == 0, "container anchored by its bottom centre to the row's")
R.Anchor(c, panel)
ok(#c.points == 1, "anchored once")
-- The pet line: Nock's own smaller tiles (Mend, Feed, the face), centred on
-- a line above the client's row (anchoring to the container is forbidden by
-- the client; Nock knows this line's width, so it can centre it itself).
ok(R.PET_ICON == 20 and R.LINE_GAP == 2, "mini tiles, two units above the client row")
ok(R.LineHeight(26) == 26 + 2 + 20, "the row is two lines tall")
ok(R.TileX(1, 1, 20, -1, 240) == 110, "one tile centred: (240 - 20) / 2")
ok(R.TileX(1, 3, 20, -1, 240) == 91 and R.TileX(3, 3, 20, -1, 240) == 91 + 2 * 19, "three tiles centred with the seam overlap")
local function tile() local t = { pts = {} }; function t:ClearAllPoints() self.pts = {} end; function t:SetPoint(p, rel, rp, x, y) self.pts[#self.pts + 1] = { p, rel, rp, x, y } end; return t end
local t1 = tile()
R.AnchorTile(t1, panel, 91, 28)
ok(t1.pts[1][1] == "BOTTOMLEFT" and t1.pts[1][2] == panel and t1.pts[1][4] == 91 and t1.pts[1][5] == 28, "a tile anchored to the panel at its computed spot on the upper line")

-- A client without the template: nil, nothing thrown.
_G.CreateFrame = function() error("unknown template") end
ok(R.Create(panel, 26, -1) == nil, "no template -> nil")
-- A client that refuses the configuration: hidden and nil.
_G.CreateFrame = function() local x = setmetatable({}, Cont); x.AddAuraGroup = function() error("nope") end; return x end
local r = R.Create(panel, 26, -1)
ok(r == nil, "refused configuration -> nil")


-- The countdown is the bare number (user, 2026-09-23: "12 s" wastes the
-- tile): a numeric rule formatter over the remaining duration, rounded up
-- like the client's own, through the button's textFormat option. Without
-- the formatter APIs the client's default text stands.
do
  local made = {}
  _G.C_StringUtil = { CreateNumericRuleFormatter = function()
    local f = { bps = {} }
    function f:AddBreakpoint(bp) self.bps[#self.bps + 1] = bp end
    made[#made + 1] = f
    return f
  end }
  _G.Enum = _G.Enum or {}
  Enum.DurationTextBindingProperty = { RemainingDuration = 0 }
  Enum.NumericRuleFormatRounding = { Nearest = 0, Up = 1, Down = 2 }
  R._durationFormat = nil  -- the earlier buttons were styled without the APIs
  local b1 = setmetatable({}, Btn)
  R.Style(b1, 24)
  local o = b1.durationOptions
  ok(o and o.textFormat and o.textFormat.formatString == "{}", "duration text: one placeholder, no unit")
  local t = b1.durationText
  ok(t.points[1] == "TOPLEFT" and t.points[2] == "BOTTOMRIGHT" and t.jh == "CENTER" and t.jv == "MIDDLE", "the countdown fills the tile, centred both ways")
  ok(b1._timeBoxed == true, "the slot is marked boxed so the text nudge moves both corners")
  local comp = o and o.textFormat.components and o.textFormat.components[1]
  ok(comp and comp.property == 0 and comp.formatter == made[1], "the remaining duration through the rule formatter")
  ok(#made == 1 and made[1].bps[1].threshold == 0 and made[1].bps[1].step == 1 and made[1].bps[1].rounding == 1 and made[1].bps[1].format == "%d", "one breakpoint: whole seconds, rounded up")
  local b2 = setmetatable({}, Btn)
  R.Style(b2, 24)
  ok(#made == 1 and b2.durationOptions.textFormat.components[1].formatter == made[1], "the formatter is built once and shared")
  _G.C_StringUtil = nil
  R._durationFormat = nil
  local b3 = setmetatable({}, Btn)
  R.Style(b3, 24)
  ok(b3.durationText and b3.durationOptions == nil, "no formatter API: the client's default text")
end

-- Hide + pin lists (user, 2026-09-26): the hide list drops IDs from the
-- short row; pinned IDs get their own any-caster, uncapped group after it
-- and are dropped from the short row so nothing shows twice.
do
  ok(next(R.IdTable(nil)) == nil and next(R.IdTable({})) == nil, "no list -> empty ID table")
  local s = R.IdTable({ 5, "7", "x", 5 })
  ok(s[5] == true and s[7] == true and s.x == nil, "set shape: numbers and numeric strings, junk skipped")
  local l = R.IdTable({ 5, "7", 5 }, "list")
  ok(#l == 2 and l[1] == 5 and l[2] == 7, "list shape: ordered, duplicates folded")

  local short, pinned = R.Filters(nil, nil)
  ok(short.maxDuration == 60 and short.excludeSpellIDs == nil, "no lists: the short row as before")
  ok(pinned.includeSpellIDs and next(pinned.includeSpellIDs) == nil, "no pins: the pinned group includes nothing")
  short, pinned = R.Filters({ 100 }, { 200 })
  ok(short.maxDuration == 60 and short.excludeSpellIDs[100] and short.excludeSpellIDs[200], "short row excludes hidden AND pinned IDs")
  ok(pinned.includeSpellIDs[200] and not pinned.includeSpellIDs[100] and pinned.maxDuration == nil, "pinned group: the pins only, no duration cap")

  _G.CreateFrame = function(kind, name, parent, template) return setmetatable({ kind = kind, parent = parent }, Cont) end
  local c2 = R.Create(panel, 26, -1, { 100 }, { 200 })
  ok(c2.order[1] == "short" and c2.order[2] == "pinned", "two groups, the pinned one after the short row")
  local pg = c2.groups.pinned
  ok(pg.filter == "HELPFUL" and pg.opts.maxFrameCount == R.PIN_FRAMES, "pinned: any caster, its own frame cap")
  ok(pg.opts.candidateFilters.includeSpellIDs[200] and c2.groups.short.opts.candidateFilters.excludeSpellIDs[100], "Create applies both lists")
  ok(pg.opts.layout.elementWidth == 26 and pg.buttons[1].time ~= nil, "pinned tiles in the same look")
  local n = 0
  R.EachButton(c2, function() n = n + 1 end)
  ok(n == 4, "EachButton walks both groups")

  ok(R.ApplyFilters(c2, { 300 }, {}) == true, "re-filter accepted")
  ok(c2.refiltered.short.excludeSpellIDs[300] and next(c2.refiltered.pinned.includeSpellIDs) == nil, "re-filter reaches both groups")
  ok(c2.reread == 1, "re-filter makes the container re-read the auras already up")
  ok(R.lastApply == "short filters ok; pinned filters ok; refresh ok", "the apply outcome is kept for the probe")

  -- A client that refuses the pinned group keeps the short row.
  _G.CreateFrame = function(kind)
    local x = setmetatable({ kind = kind }, Cont)
    x.AddAuraGroup = function(self, k, f, o)
      if k == "pinned" then error("nope") end
      return Cont.AddAuraGroup(self, k, f, o)
    end
    return x
  end
  local c3 = R.Create(panel, 26, -1, nil, { 200 })
  ok(c3 and c3.groups.short and not c3.groups.pinned and c3._nockPinned == nil, "pinned group refused -> short row stands")
  ok(R.ApplyFilters(c3, nil, { 200 }) == true and c3.refiltered.pinned == nil, "re-filter skips the missing pinned group")
end

-- The settings' "Buffs up now" list and the add form (user, 2026-09-26).
do
  ok(R.ShownByRule({ sourceUnit = "player", duration = 12 }) == true, "own 12 s proc: shown by the row itself")
  ok(R.ShownByRule({ sourceUnit = "player", duration = 0 }) == false, "own permanent aura (an aspect): not shown")
  ok(R.ShownByRule({ sourceUnit = "player", duration = 3600 }) == false, "own hour-long buff (a flask): not shown")
  ok(R.ShownByRule({ sourceUnit = "party1", duration = 10 }) == false, "someone else's buff: not shown")

  local auras = {
    { spellId = 13165, name = "Aspect of the Hawk", icon = 1, sourceUnit = "player", duration = 0 },
    { spellId = 6150, name = "Quick Shots", icon = 2, sourceUnit = "player", duration = 12 },
    { spellId = 3045, name = "Rapid Fire", icon = 3, sourceUnit = "player", duration = 15 },
    { spellId = 6150, name = "Quick Shots", icon = 2, sourceUnit = "player", duration = 12 },
    { spellId = 99, name = "Some Debuff", isHelpful = false },
    { spellId = 28520, name = "Flask of Relentless Assault", icon = 4, sourceUnit = "player", duration = 7200 },
  }
  local c = R.Candidates(auras, { 28520 }, { 3045 })
  ok(#c == 4, "helpful auras, one line per id, debuffs left out")
  ok(c[1].name == "Quick Shots" and c[2].name == "Rapid Fire" and c[1].rule and c[2].rule, "the ones the row shows come first, by name")
  ok(c[3].name == "Aspect of the Hawk" and not c[3].rule, "then the rest, by name")
  ok(c[2].hidden == true and c[4].pinned == true and c[1].pinned == false and c[1].hidden == false, "pinned / hidden marked")
  ok(#R.Candidates(nil, nil, nil) == 0, "no auras -> empty list")

  local byAura = function(n) if n == "Quick Shots" then return { spellId = 6150 } end end
  local bySpell = function(n) if n == "Rapid Fire" then return 3045 end end
  ok(R.ResolveEntry(" 6150 ", byAura, bySpell) == 6150, "digits are the id")
  ok(R.ResolveEntry("Quick Shots", byAura, bySpell) == 6150, "a name up now resolves to the aura's own id")
  ok(R.ResolveEntry("Rapid Fire", byAura, bySpell) == 3045, "otherwise a spell name")
  ok(R.ResolveEntry("Nope", byAura, bySpell) == nil and R.ResolveEntry("  ", byAura, bySpell) == nil, "unknown or empty -> nil")

  local src = { 1, 2 }
  local l = R.ListWith(src, 3, true)
  ok(#l == 3 and l[3] == 3 and #src == 2, "add returns a new list")
  ok(#R.ListWith(l, 3, true) == 3, "adding twice keeps one")
  l = R.ListWith(l, 1, false)
  ok(#l == 2 and l[1] == 2 and l[2] == 3, "remove drops the id")
end

ok(R.LineHeight(26) == 26 + R.LINE_GAP + R.PET_ICON, "line height: default pet line")
ok(R.LineHeight(39, 30) == 39 + R.LINE_GAP + 30, "line height: sized pet line")

print(("forever_aura_row: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
