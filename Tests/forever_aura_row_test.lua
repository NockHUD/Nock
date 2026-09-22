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
  return { SetAllPoints = function() end, SetPoint = function() end, SetColorTexture = function() end, SetTexCoord = function() end }
end
local Btn = {}
Btn.__index = Btn
function Btn:CreateTexture() return region() end
function Btn:CreateFontString() return region() end
function Btn:SetSize(w, h) self.w, self.h = w, h end
function Btn:SetIcon(t) self.iconSet = t end
function Btn:SetDurationText(fs) self.durationText = fs end
function Btn:IsShown() error("secret boolean") end

local Cont = {}
Cont.__index = Cont
function Cont:SetUnit(u) self.unit = u end
function Cont:SetFlowLayoutAxis(a) self.axis = a end
function Cont:SetFlowLayoutGrowthDirection(h, v) self.grow = { h, v } end
function Cont:SetFlowLayoutAnchorPoint(p) self.anchor = p end
function Cont:AddAuraGroup(k, f, o)
  self.group = { key = k, filter = f, opts = o }
  self.buttons = {}
  for i = 1, 2 do self.buttons[i] = setmetatable({}, Btn); o.initializeFrame(self.buttons[i]) end
end
function Cont:GetAuraGroupFrame(k, i) return self.buttons and self.buttons[i] or nil end
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

print(("forever_aura_row: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
