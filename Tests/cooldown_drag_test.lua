-- Tests/cooldown_drag_test.lua
-- UI/CooldownDrag.lua: DropSlot geometry and the press -> lift -> drop / cancel machine.
-- Run from the repo root: luajit Tests/cooldown_drag_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. name) end
end

local cx, cy, down = 0, 0, true
_G.GetCursorPosition = function() return cx, cy end
_G.IsMouseButtonDown = function() return down end
_G.UIParent = {}
local function stubFrame()
  local f = { shown = false }
  local noop = function() end
  for _, m in ipairs({ "SetSize", "SetPoint", "ClearAllPoints", "SetFrameStrata", "SetAllPoints", "SetTexture",
                       "EnableKeyboard", "SetPropagateKeyboardInput", "RegisterEvent", "SetAlpha" }) do f[m] = noop end
  function f:SetScript(n, fn) self[n] = fn end
  function f:Show() self.shown = true end
  function f:Hide() self.shown = false end
  function f:CreateTexture() return stubFrame() end
  return f
end
_G.CreateFrame = function() return stubFrame() end
local Nock = {}
_G.LibStub = function() return { GetAddon = function() return Nock end } end
dofile("UI/CooldownDrag.lua")
local D = Nock.CooldownDrag

-- DropSlot
local rows = {
  { index = 1, top = 100, bottom = 60, left = 0, right = 120, tiles = { { l = 0, r = 40, key = "A" }, { l = 40, r = 80, key = "B" }, { l = 80, r = 120, key = "C" } } },
  { index = 2, top = 55, bottom = 30, left = 0, right = 60, tiles = { { l = 0, r = 30, key = "D" }, { l = 30, r = 60, key = "E" } } },
}
local ri, ii = D.DropSlot(rows, 10, 80, 4)
ok(ri == 1 and ii == 1, "left half of the first tile -> before it")
ri, ii = D.DropSlot(rows, 70, 80, 4)
ok(ri == 1 and ii == 3, "right half of B -> before C")
ri, ii = D.DropSlot(rows, 150, 80, 4)
ok(ri == 1 and ii == 4, "right of the row (within slack) -> end")
ri, ii = D.DropSlot(rows, 10, 40, 4)
ok(ri == 2 and ii == 1, "second row")
ok(D.DropSlot(rows, 10, 200, 4) == nil, "above every row -> nil")
ok(D.DropSlot(rows, -50, 80, 4) == nil, "left of the row -> nil")
local er, ei = D.DropSlot({ { index = 2, top = 20, bottom = 0, left = 0, right = 30, tiles = {} } }, 5, 10, 4)
ok(er == 2 and ei == 1, "an empty row accepts a drop at 1")

-- host
local log = {}
local host = {
  DragRows = function() return rows end,
  DragCaret = function(_, r, i) log.caret = r and (r .. ":" .. i) or "off" end,
  DragDrop = function(_, key, r, i) log.drop = key .. ">" .. r .. ":" .. i end,
  TileClick = function(_, key) log.click = key end,
  DragIcon = function() return 1 end,
}

-- a click: press and release without moving past the threshold
cx, cy, down = 10, 80, true
D:Press(host, "A")
cx = 12; D:Tick()
ok(not D.active, "under the threshold stays a press")
D:Release()
ok(log.click == "A" and not log.drop and not D.pressed, "a short press is a click")

-- a drag to row 2, slot 2
log = {}
cx, cy, down = 10, 80, true
D:Press(host, "A")
cx, cy = 40, 40; D:Tick()
ok(D.active and log.caret == "2:2", "past the threshold lifts, caret follows")
D:Release()
ok(log.drop == "A>2:2" and log.caret == "off" and not D.active and not D.pressed, "release drops at the caret")

-- release outside every row cancels
log = {}
cx, cy = 10, 80; D:Press(host, "B")
cx, cy = 10, 500; D:Tick(); D:Release()
ok(not log.drop and log.caret == "off", "a drop outside the grid cancels (nothing removed)")

-- Esc / combat: Cancel
log = {}
cx, cy = 10, 80; D:Press(host, "C")
cx = 60; D:Tick(); D:Cancel()
ok(not log.drop and not D.active and not D.pressed, "Cancel ends the drag without a drop")

-- mouse-up never arrives (button released without its own OnMouseUp event)
log = {}
cx, cy, down = 10, 80, true
D:Press(host, "A"); cx, cy = 40, 40; D:Tick()
down = false; D:Tick()
ok(log.drop == "A>2:2" and not D.pressed, "a released button seen by the tick ends the drag")

print(("cooldown_drag: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
