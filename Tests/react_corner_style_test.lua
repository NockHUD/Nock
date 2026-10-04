-- Tests/react_corner_style_test.lua
-- Standalone LuaJIT tests for the React corner icons' Redtuzk style: the rectangle geometry, the centred-pair anchors and the mark's active-only gate.
-- Run from the repo root: luajit Tests/react_corner_style_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end

-- Frame stub: records size, points, visibility.
local function newFrame()
  local f = { shown = false, points = {} }
  function f:SetSize(w, h) self.w, self.h = w, h end
  function f:SetWidth(w) self.w = w end
  function f:ClearAllPoints() self.points = {} end
  function f:SetPoint(point, rel, relPoint, x, y) self.points[#self.points + 1] = { point, rel, relPoint, x, y } end
  function f:Show() self.shown = true end
  function f:Hide() self.shown = false end
  function f:IsShown() return self.shown end
  function f:SetMovable() end
  function f:SetClampedToScreen() end
  function f:RegisterForDrag() end
  function f:EnableMouse() end
  function f:SetScript() end
  function f:SetBackdropBorderColor() end
  f.icon = { SetVertexColor = function() end }
  return f
end

local locked = true
local painted = {}
local Nock = {
  db = { profile = {
    reactShowAspectIcon = true, reactShowMarkIcon = true,
    reactCornerIconSize = 42, reactCornerIconX = 30, reactCornerIconY = 50,
    reactAspectIconPos = false, reactMarkIconPos = false,
    reactAspectRectPos = false, reactMarkRectPos = false,
  } },
  Constants = { COLORS = { BORDER_UNLOCK = { 0, 1, 0, 1 } }, SpellID = { ASPECT_HAWK = 27044 } },
  parentFrame = newFrame(),
  API = { SpellIcon = function(id) return "icon" .. id end, SpellInfo = function() end },
  UI = {
    CreateReactSlot = function() return newFrame() end,
    SetReactSlotSize = function(slot, size) slot:SetSize(size, size) end,
    PaintReactSlot = function(slot, item) painted[slot] = { coords = item.coords, sub = item.sub, desat = item.desat } end,
    RegisterNudgeable = function() end,
  },
}
function Nock:NewModule(name)
  local m = { RegisterMessage = function() end }
  self._mods = self._mods or {}
  self._mods[name] = m
  return m
end
function Nock:GetModule(name) return self._mods and self._mods[name] end
function Nock.HudIsReact() return true end
function Nock.WizardHides() return false end
function Nock.IsLockedFor() return locked end

_G.LibStub = setmetatable({}, { __call = function() return { GetAddon = function() return Nock end } end })
_G.GetTime = function() return 100 end
_G.unpack = _G.unpack or table.unpack

dofile("UI/Frame_ReactCorners.lua")
local RC = Nock:GetModule("ReactCorners")
local p = Nock.db.profile

-- Pure geometry: 2:1 box, icon cropped to its middle band to keep its aspect.
do
  local w, h, coords = RC.RectGeometry(42)
  ok(w == 42 and h == 21, "rect: 42 -> 42 x 21")
  ok(coords[1] == 0.08 and coords[2] == 0.92, "rect: full horizontal crop kept")
  local span = coords[4] - coords[3]
  ok(math.abs(span - 0.84 * (h - 2) / (w - 2)) < 1e-9, "rect: vertical span matches the inner box ratio")
  ok(math.abs((coords[3] + coords[4]) / 2 - 0.5) < 1e-9, "rect: crop centred vertically")
end

-- Pure anchors: one icon sits centred, a pair grows out from the middle.
do
  local pt, x = RC.RectAnchor("aspect", false)
  ok(pt == "BOTTOM" and x == 0, "anchor: lone aspect centred")
  pt, x = RC.RectAnchor("mark", false)
  ok(pt == "BOTTOM" and x == 0, "anchor: lone mark centred")
  local pa, xa = RC.RectAnchor("aspect", true)
  local pm, xm = RC.RectAnchor("mark", true)
  ok(pa == "BOTTOMRIGHT" and xa < 0 and pm == "BOTTOMLEFT" and xm == -xa, "anchor: pair mirrors around the centre")
end

RC:OnInitialize()
local state = { player = { aspect = { icon = "hawk" } }, target = {} }

-- Nock style: unchanged squares, greyed mark when the target has none.
RC:Refresh(state)
ok(RC.aspect.w == 42 and RC.aspect.h == 42, "nock: square aspect")
ok(RC.aspect.points[1][1] == "BOTTOMRIGHT" and RC.aspect.points[1][3] == "TOPLEFT" and RC.aspect.points[1][4] == -30, "nock: aspect on the top-left corner")
ok(RC.mark:IsShown() and painted[RC.mark].desat == true, "nock: missing mark shows greyed")
ok(painted[RC.aspect].coords == nil, "nock: stock icon crop")

-- Redtuzk style.
p.reactCornerStyle = "redtuzk"
RC:ApplyLayout()
RC:Refresh(state)
ok(RC.aspect.w == 42 and RC.aspect.h == 21, "redtuzk: rectangle aspect")
ok(RC.aspect:IsShown() and not RC.mark:IsShown(), "redtuzk: mark hidden while not on the target")
ok(RC.aspect.points[1][1] == "BOTTOM" and RC.aspect.points[1][3] == "TOP" and RC.aspect.points[1][4] == 0 and RC.aspect.points[1][5] == 80, "redtuzk: lone aspect centred above the cluster")
ok(painted[RC.aspect].coords ~= nil, "redtuzk: rectangle crop painted")

state.target.huntersMark = { icon = "hm", expirationTime = 200, duration = 120, sourceName = "Redtuzk" }
RC:Refresh(state)
ok(RC.mark:IsShown() and RC.mark.h == 21, "redtuzk: mark rectangle shows while active")
ok(RC.aspect.points[1][1] == "BOTTOMRIGHT" and RC.aspect.points[1][4] < 0 and RC.mark.points[1][1] == "BOTTOMLEFT" and RC.mark.points[1][4] > 0, "redtuzk: pair grows from the centre")
ok(painted[RC.mark].sub == nil, "redtuzk: no caster caption")

state.target.huntersMark = nil
RC:Refresh(state)
ok(not RC.mark:IsShown() and RC.aspect.points[1][1] == "BOTTOM", "redtuzk: aspect re-centres when the mark drops")

-- Aspect toggle off: the mark sits centred on its own.
p.reactShowAspectIcon = false
state.target.huntersMark = { icon = "hm", expirationTime = 200, duration = 120 }
RC:Refresh(state)
ok(not RC.aspect:IsShown() and RC.mark.points[1][1] == "BOTTOM", "redtuzk: lone mark centred")
p.reactShowAspectIcon = true

-- Unlocked: the mark previews with no target so it can be placed.
state.target.huntersMark = nil
locked = false
RC:Refresh(state)
ok(RC.mark:IsShown(), "redtuzk: mark previews while unlocked")
locked = true

-- A dragged rectangle keeps its own spot; the other one centres alone. The
-- Nock style's stored corner position is a separate key.
p.reactAspectRectPos = { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", x = 5, y = 7 }
state.target.huntersMark = { icon = "hm", expirationTime = 200, duration = 120 }
RC:ApplyLayout()
RC:Refresh(state)
ok(RC.aspect.points[1][1] == "BOTTOMLEFT" and RC.aspect.points[1][4] == 5, "redtuzk: free aspect position wins")
ok(RC.mark.points[1][1] == "BOTTOM", "redtuzk: mark centres alone beside a free aspect")
p.reactCornerStyle = "nock"
RC:ApplyLayout()
RC:Refresh(state)
ok(RC.aspect.h == 42 and RC.aspect.points[1][1] == "BOTTOMRIGHT", "nock: back to the corner, rectangle position not applied")
ok(painted[RC.mark].sub == "Redtuzk" or painted[RC.mark].sub == nil, "nock: caption path intact")

print(("react_corner_style_test: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
