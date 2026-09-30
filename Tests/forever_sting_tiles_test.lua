-- Tests/forever_sting_tiles_test.lua
-- Forever/StingTiles.lua: a sting tile of the cooldown grid is covered by a
-- one-button aura container on the target (own harmful auras, the sting's
-- ranks), which the client fills with the true countdown.
-- Run from the repo root: luajit Tests/forever_sting_tiles_test.lua

local pass, fail = 0, 0
local function ok(c, n) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. n) end end

local looked, registered = {}, {}
local Nock = {
  UI = {
    IconCoords = function(w, h, zoom) return w, h, zoom or -1, 0 end,
    ApplyReactTextLook = function(fs) looked[#looked + 1] = fs end,
    RegisterFontString = function(fs, key, style, react) registered[#registered + 1] = { fs, react } end,
  },
  ForeverAuraRow = {
    IdTable = function(list) local t = {}; for _, id in ipairs(list) do t[id] = true end; return t end,
    DurationFormat = function() return { textFormat = "bare" } end,
  },
}
_G.LibStub = function() return { GetAddon = function() return Nock end } end
_G.AnchorUtil = { FlowLayoutAxis = { Horizontal = 0, Vertical = 1 }, FlowDirection = { Down = -1, Left = -1, Right = 1, Up = 1 } }
_G.AuraContainerSortMethod = { Default = 0, Expiration = 4 }
_G.AuraContainerSortDirection = { Normal = 0, Reverse = 1 }

-- Fakes: regions and frames that record what they are told.
local function region()
  local r = { points = {} }
  function r:SetAllPoints(to) self.all = to end
  function r:SetPoint(p, rel) self.points[#self.points + 1] = { p, rel } end
  function r:SetColorTexture() end
  function r:SetTexCoord(...) self.coords = { ... } end
  function r:SetJustifyH(j) self.jh = j end
  function r:SetJustifyV(j) self.jv = j end
  return r
end
local Frame = {}
Frame.__index = Frame
function Frame:CreateTexture() return region() end
function Frame:CreateFontString() return region() end
function Frame:SetAllPoints(to) self.all = to end
function Frame:SetSize(w, h) self.w, self.h = w, h end
function Frame:SetFrameLevel(l) self.level = l end
function Frame:GetFrameLevel() return self.level or 1 end
function Frame:GetRegions() return end
function Frame:ClearAllPoints() self.points = {} end
function Frame:SetPoint(p, rel, rp, x, y) self.points = self.points or {}; self.points[#self.points + 1] = { p, rel, rp, x, y } end
function Frame:Show() self.shown = true end
function Frame:Hide() self.shown = false end
function Frame:EnableMouse(on) self.mouse = on end
-- an aura button
function Frame:SetIcon(t) self.iconSet = t end
function Frame:SetDurationCooldown(c) self.swipe = c end
function Frame:SetDurationText(fs, o) self.durationText, self.durationOptions = fs, o end
function Frame:IsShown() error("secret boolean") end
-- an aura container
function Frame:SetUnit(u) self.unit = u end
function Frame:SetFlowLayoutAxis(a) self.axis = a end
function Frame:SetFlowLayoutGrowthDirection(h, v) self.grow = { h, v } end
function Frame:SetFlowLayoutAnchorPoint(p) self.flowAnchor = p end
function Frame:AddAuraGroup(k, f, o) self.group = { key = k, filter = f, opts = o } end
function Frame:SetAuraGroupLayout(k, l) self.relaid = { k, l } end
function Frame:SetAuraGroupCandidateFilters(k, f) self.refiltered = { k, f } end
function Frame:UpdateAllAuras() self.reread = (self.reread or 0) + 1 end
function Frame:SetEnabled(e) self.enabled = e end

local created = {}
local function newFrame(kind, name, parent, template)
  local f = setmetatable({ kind = kind, name = name, parent = parent, template = template }, Frame)
  created[#created + 1] = f
  return f
end
_G.CreateFrame = newFrame

dofile("Forever/StingTiles.lua")
local ST = Nock.ForeverStingTiles
ok(ST and ST.GROUP == "sting" and ST.FILTER == "HARMFUL|PLAYER", "module: own harmful auras")

-- The ids a sting's aura can carry: the ranks the client still names like
-- rank 1, plus the spellbook's own id for that name (Forever renumbered some).
do
  local NAMES = { [3043] = "Scorpid Sting", [14275] = "Old Rank", [1300002] = "Scorpid Sting", [1978] = "Serpent Sting", [13549] = "Serpent Sting" }
  local nameOf = function(id) return NAMES[id] end
  ok(table.concat(ST.Ids({ 3043, 14275 }, "Scorpid Sting", nameOf, { ["Scorpid Sting"] = 1300002 }), " ") == "3043 1300002",
     "renamed ranks dropped, the spellbook's id added")
  ok(table.concat(ST.Ids({ 1978, 13549 }, "Serpent Sting", nameOf, { ["Serpent Sting"] = 13549 }), " ") == "1978 13549",
     "a spellbook id already kept is not added twice")
  ok(#ST.Ids({ 1978 }, nil, nameOf, nil) == 0, "no name -> nothing")
  ok(#ST.Ids(nil, "Serpent Sting", nameOf, { ["Serpent Sting"] = true }) == 0, "no candidates and a non-numeric book entry -> nothing")
  ok(ST.Signature({ 5, 3, 9 }) == "3,5,9" and ST.Signature({}) == "", "a signature is the sorted ids")
end

-- Create: one tile on the target, filtered to the ids.
local grid = { name = "grid" }
local tile = ST.Create(grid, "Serpent", 44, 32, { 1978, 13549 }, 8)
local c = tile and tile.c
ok(c and c.kind == "AuraContainer" and c.template == "CustomAuraContainerTemplate" and c.parent == grid and c.name == "NockStingTileSerpent",
   "a named container on the grid")
ok(c.unit == "target" and c.group.key == "sting" and c.group.filter == "HARMFUL|PLAYER", "own harmful auras of the target")
ok(c.group.opts.maxFrameCount == 1 and c.group.opts.candidateFilters.includeSpellIDs[13549] == true, "one tile, the sting's ids only")
ok(c.group.opts.sortMethod == 4 and c.group.opts.sortDirection == 0, "soonest-ending first")
ok(c.group.opts.layout.elementWidth == 44 and c.group.opts.layout.elementHeight == 32, "laid out at the tile's size")
ok(c.axis == 0 and c.flowAnchor == "TOPLEFT" and c.enabled == true and c.shown == true, "flows from the top-left, enabled and shown")

-- The client asks for a button: styled once, in the grid tile's look.
local b = setmetatable({}, Frame)
c.group.opts.initializeFrame(b)
ok(b.iconSet and b.swipe and b.durationText, "a button is handed an icon, a swipe and a countdown")
ok(b.w == 44 and b.h == 32 and b.iconSet.coords[1] == 44 and b.iconSet.coords[3] == 8, "sized to the tile, the icon cropped at the grid's zoom")
ok(b.durationOptions and b.durationOptions.textFormat == "bare", "the countdown is the bare number")
ok(b.durationText.jh == "CENTER" and b.durationText.jv == "MIDDLE", "the countdown is centred in the tile")
ok(looked[1] == b.durationText and registered[1][1] == b.durationText and registered[1][2] == true, "the countdown takes the grid's text look, now and on a media change")
ok(b.mouse == false, "the button takes no mouse (no tooltip over the HUD)")
ok(#tile.buttons == 1, "the tile remembers its buttons")
local icon = b.iconSet
c.group.opts.initializeFrame(b)
ok(b.iconSet == icon and #tile.buttons == 1, "styling is idempotent")

-- Sync: every placed sting entry gets its container over its slot.
local function slot(key, w, h, debuff)
  local s = setmetatable({ level = 3, w = w, h = h, shown = true }, Frame)
  s._entry = key and { key = key, id = 1978, debuff = debuff } or nil
  function s:GetWidth() return self.w end
  function s:GetHeight() return self.h end
  function s:IsShown() return self.shown end
  return s
end
created = {}
local tiles = {}
local function containers() local n = 0; for _, f in ipairs(created) do if f.kind == "AuraContainer" then n = n + 1 end end; return n end
local idsFor = { Serpent = { 1978, 13549 }, Viper = { 3034 } }
local env = { inCombat = false, zoom = 8, idsFor = function(e) return idsFor[e.key] end }
local s1, s2, s3 = slot("Arc", 40, 32, nil), slot("Serpent", 40, 32, true), slot(nil, 40, 32)
local pool = { s1, s2, s3 }
ok(ST.Sync(tiles, pool, grid, env) == false, "out of combat: nothing left pending")
ok(containers() == 1 and tiles.Serpent and tiles.Serpent.c == created[1], "one container, for the sting entry only")
local sc = tiles.Serpent.c
ok(sc.points[1][1] == "TOPLEFT" and sc.points[1][2] == s2 and sc.points[1][3] == "TOPLEFT", "anchored over its slot")
ok(sc.level == 3 + ST.LEVEL_ABOVE, "above the slot's own swipe and text")
ok(sc.group.opts.layout.elementWidth == 40, "built at the slot's size")
local anchors = #sc.points
ST.Sync(tiles, pool, grid, env)
ok(containers() == 1 and #sc.points == anchors and sc.relaid == nil and sc.refiltered == nil, "a second sync changes nothing")

-- A resize (another tile joined the row) and a new rank, out of combat.
local sb = setmetatable({}, Frame)
sc.group.opts.initializeFrame(sb)
s2.w = 36
idsFor.Serpent = { 1978, 13549, 13550 }
ST.Sync(tiles, pool, grid, env)
ok(sc.relaid and sc.relaid[2].elementWidth == 36 and sb.w == 36 and sb.h == 32, "a resize re-lays the group and its buttons")
ok(sc.refiltered and sc.refiltered[2].includeSpellIDs[13550] == true and sc.reread == 1, "new ids re-filter and re-read")

-- In combat: placement only; size and filters wait.
env.inCombat = true
sc.relaid, sc.refiltered = nil, nil
s2.w = 30
idsFor.Serpent = { 1978 }
ok(ST.Sync(tiles, pool, grid, env) == true, "in combat: a resize is left pending")
ok(sc.relaid == nil and sc.refiltered == nil and sb.w == 36, "nothing resized or re-filtered in combat")
local s4 = slot("Viper", 32, 24, true)
pool[#pool + 1] = s4
ok(ST.Sync(tiles, pool, grid, env) == true and tiles.Viper == nil and containers() == 1, "in combat: a new tile is not built yet")
env.inCombat = false
ok(ST.Sync(tiles, pool, grid, env) == false and tiles.Viper and sc.relaid[2].elementWidth == 30 and sc.refiltered ~= nil, "after combat: built, resized, re-filtered")

-- A new rank trained in combat: the ids are looked at once combat ends.
env.inCombat = true
ST.MarkIdsStale(tiles)
ok(ST.Sync(tiles, pool, grid, env) == true, "in combat: stale ids are left pending")
env.inCombat = false
idsFor.Serpent = { 1978, 13551 }
ok(ST.Sync(tiles, pool, grid, env) == false and sc.refiltered[2].includeSpellIDs[13551] == true, "after combat: re-filtered")

-- The entry moves to another slot; then leaves the grid; then returns.
s1._entry, s2._entry = s2._entry, s1._entry
ST.Sync(tiles, pool, grid, env)
ok(sc.points[#sc.points][2] == s1 and #sc.points == 1, "moved: re-anchored to the new slot")
s1._entry = { key = "Arc" }
ST.Sync(tiles, pool, grid, env)
ok(sc.enabled == false and sc.shown == false, "off the grid: disabled and hidden")
local rereads = sc.reread
s2._entry = { key = "Serpent", id = 1978, debuff = true }
ST.Sync(tiles, pool, grid, env)
ok(sc.enabled == true and sc.shown == true and sc.points[1][2] == s2 and sc.reread == rereads + 1, "back on the grid: enabled, shown, re-read")
s2.shown = false
ST.Sync(tiles, pool, grid, env)
ok(sc.shown == false, "a hidden slot's tile is parked")
s2.shown = true
ST.Sync(tiles, pool, grid, env)

-- A target change re-reads every live tile (the container follows the unit's
-- aura events, not the token moving to another unit).
local before, vbefore = sc.reread, tiles.Viper.c.reread or 0
s4._entry = nil
ST.Sync(tiles, pool, grid, env)
ST.RereadAll(tiles)
ok(sc.reread == before + 1 and (tiles.Viper.c.reread or 0) == vbefore, "target change: live tiles re-read, parked ones left alone")

-- A client without the template: tried once, never again, nothing thrown.
_G.CreateFrame = function() error("unknown template") end
local t2 = {}
ok(ST.Sync(t2, { slot("Scorpid", 32, 24, true) }, grid, env) == false and t2.Scorpid == false, "no template: remembered as unavailable")
local tries = 0
_G.CreateFrame = function() tries = tries + 1; error("unknown template") end
ST.Sync(t2, { slot("Scorpid", 32, 24, true) }, grid, env)
ok(tries == 0, "not retried")
-- A client that refuses the configuration: hidden, unavailable.
local refused
_G.CreateFrame = function(kind, ...)
  local f = newFrame(kind, ...)
  if kind == "AuraContainer" then refused = f; f.AddAuraGroup = function() error("nope") end end
  return f
end
ok(ST.Create(grid, "X", 32, 24, {}, 8) == nil and refused.shown == false, "refused configuration -> nil, hidden")
ST.RereadAll(t2)
ok(true, "re-reading with an unavailable tile does not throw")

print(("forever_sting_tiles: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
