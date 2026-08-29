-- Tests/nudge_test.lua
-- Standalone LuaJIT tests for the pure nudge math in UI/EditMode.lua.
-- Run from the repo root: luajit Tests/nudge_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end

-- Minimal Ace/WoW surface. EditMode's module table is created via NewModule;
-- the pure helpers hang off Nock.UI, so a stub module table is enough.
local Nock = { UI = {} }
function Nock:NewModule() return {} end
Nock.Constants = { COLORS = { BG = {0,0,0,1}, BORDER = {0,0,0,1}, BORDER_UNLOCK = {0,1,0,1} } }
_G.LibStub = function() return { GetAddon = function() return Nock end } end
_G.CreateFrame = function() return {} end
_G.UIParent = {}
_G.InCombatLockdown = function() return false end

dofile("UI/EditMode.lua")

local CN = Nock.UI.ComputeNudge
local LIVE = { point = "CENTER", relPoint = "CENTER", x = 100, y = 50 }

-- 1. Direction mapping. Up is +y and right is +x for every anchor point WoW
--    uses, so there is no per-frame direction table to get wrong.
local stored = { point = "TOPLEFT", relPoint = "BOTTOMLEFT", x = 10, y = 20 }
ok(CN(stored, LIVE, "up",    1).y == 21, "up: y +1")
ok(CN(stored, LIVE, "down",  1).y == 19, "down: y -1")
ok(CN(stored, LIVE, "right", 1).x == 11, "right: x +1")
ok(CN(stored, LIVE, "left",  1).x ==  9, "left: x -1")

-- 2. The step multiplier (shift-click).
ok(CN(stored, LIVE, "up",    10).y == 30, "shift up: y +10")
ok(CN(stored, LIVE, "left",  10).x ==  0, "shift left: x -10")

-- 3. The off-axis coordinate and both anchor fields survive untouched.
local r = CN(stored, LIVE, "up", 1)
ok(r.x == 10,                     "nudge: off-axis x unchanged")
ok(r.point    == "TOPLEFT",       "nudge: point preserved")
ok(r.relPoint == "BOTTOMLEFT",    "nudge: relPoint preserved")

-- 4. A new table comes back; the stored one is never mutated in place. The
--    manager hands the result to spec.set, which owns the write.
ok(r ~= stored,    "nudge: returns a new table")
ok(stored.y == 20, "nudge: stored table not mutated")

-- 5. Seeding. medallionPos defaults to `false` and a free row is unseeded until
--    its first layout pass — both must nudge from the LIVE frame position, not
--    from {0,0}, or the first click teleports the frame.
ok(CN(nil,   LIVE, "up",    1).y == 51,  "seed from live when stored is nil")
ok(CN(false, LIVE, "right", 1).x == 101, "seed from live when stored is false")
ok(CN(nil,   LIVE, "up",    1).point == "CENTER", "seed: live anchor adopted")

-- 6. A stored table missing `point` is junk (a half-written SavedVariable) and
--    seeds from live too, rather than producing an unanchorable position.
ok(CN({ x = 5, y = 5 }, LIVE, "up", 1).y == 51, "seed from live when stored has no point")

-- 7. The registry keeps registration order and hands back frame + spec pairs.
local fA, fB = {}, {}
Nock.UI.RegisterNudgeable(fA, { label = "A", get = function() end,
                                set = function() end, default = function() end })
Nock.UI.RegisterNudgeable(fB, { label = "B", get = function() end,
                                set = function() end, default = function() end })
local list = Nock.UI.GetNudgeables()
ok(#list == 2,                  "registry: two entries")
ok(list[1].frame == fA,         "registry: order preserved")
ok(list[2].spec.label == "B",   "registry: spec carried")

-- 8. Registering the same frame twice replaces rather than duplicates — module
--    OnInitialize can run again on a profile switch.
Nock.UI.RegisterNudgeable(fA, { label = "A2", get = function() end,
                                set = function() end, default = function() end })
list = Nock.UI.GetNudgeables()
ok(#list == 2,                "registry: re-register does not duplicate")
ok(list[1].spec.label == "A2", "registry: re-register replaces the spec")

-- 9. ResetEntry must not hand the live Nock.Defaults table to set(). Storing it
--    by reference would make the next nudge mutate the defaults themselves, so
--    every frame sharing that default would drift with it.
local DEFAULTS = { point = "CENTER", relPoint = "CENTER", x = 250, y = 0 }
local written
local entry = {
  frame = {},
  spec  = {
    label   = "Misdirection",
    get     = function() return written end,
    set     = function(pos) written = pos end,
    default = function() return DEFAULTS end,
  },
}
Nock.EditMode:ResetEntry(entry)
ok(written ~= nil,              "reset: set was called")
ok(written ~= DEFAULTS,         "reset: a copy is stored, not the defaults table")
ok(written.x == 250,            "reset: x copied")
ok(written.y == 0,              "reset: y copied")
ok(written.point == "CENTER",   "reset: point copied")
written.x = 999
ok(DEFAULTS.x == 250,           "reset: mutating the stored copy leaves defaults intact")

-- 10. A `false` default (the medallion, which falls back to screen centre)
--     passes straight through rather than being copied into an empty table.
local medWritten
Nock.EditMode:ResetEntry({ frame = {}, spec = {
  label = "Medallion", get = function() end,
  set = function(pos) medWritten = pos end, default = function() return false end } })
ok(medWritten == false, "reset: a false default passes through unchanged")

-- 11. A `nil` default means the spec already reset itself as a side effect (how
--     a free-mode row clears its elementPositions entry) — set() must NOT be
--     called with nil, which would crash on pos.point.
local rowCalled = false
Nock.EditMode:ResetEntry({ frame = {}, spec = {
  label = "SwingTimers", get = function() end,
  set = function() rowCalled = true end, default = function() return nil end } })
ok(rowCalled == false, "reset: a nil default skips set() instead of crashing it")

-- 12. Pad visibility is a four-way AND. Showing every pad at once buried the
--     screen, so a pad now appears only for the ONE selected frame — click a
--     frame to select it, click another to switch.
local PV = Nock.UI.PadVisible
ok(PV(false, true,  true,  true ) == true,  "visible: unlocked + shown + gated-in + selected")
ok(PV(true,  true,  true,  true ) == false, "hidden: locked")
ok(PV(false, false, true,  true ) == false, "hidden: target not shown")
ok(PV(false, true,  false, true ) == false, "hidden: spec gate says no (grid-mode row)")
ok(PV(false, true,  true,  false) == false, "hidden: not the selected frame")

-- 13. Selection is by frame, and switching moves it rather than accumulating.
--     Repaint is stubbed out: this exercises the selection bookkeeping, and
--     building real pads needs a WoW frame factory the harness doesn't have.
local repaints = 0
Nock.EditMode.RefreshPads = function() repaints = repaints + 1 end

local f1, f2 = {}, {}
local spec = { label = "x", get = function() end, set = function() end, default = function() end }
Nock.UI.RegisterNudgeable(f1, spec)
Nock.UI.RegisterNudgeable(f2, spec)
Nock.EditMode:SelectByFrame(f1)
ok(Nock.EditMode:IsSelected(f1) == true,  "select: f1 selected")
ok(Nock.EditMode:IsSelected(f2) == false, "select: f2 not selected")
Nock.EditMode:SelectByFrame(f2)
ok(Nock.EditMode:IsSelected(f1) == false, "select: switching deselects f1")
ok(Nock.EditMode:IsSelected(f2) == true,  "select: f2 now selected")

-- 14. Locking clears the selection, so unlocking again starts clean rather than
--     popping a pad next to whatever was last touched.
Nock.EditMode:ClearSelection()
ok(Nock.EditMode:IsSelected(f2) == false, "select: cleared")

-- 15. Re-selecting the frame that is already selected is a no-op — no wasted
--     teardown/rebuild of the pad on every mousedown while dragging.
Nock.EditMode:SelectByFrame(f1)
local before = repaints
Nock.EditMode:SelectByFrame(f1)
ok(repaints == before, "select: re-selecting the same frame does not repaint")

-- 16. A lock change drops the selection, so unlocking again starts clean rather
--     than popping a pad next to whatever was last touched.
Nock.EditMode:OnLockChanged()
ok(Nock.EditMode:IsSelected(f1) == false, "lock change: selection dropped")

-- 17. spec.capture overrides GetPoint() as the seed. The cast bar is welded to
--     the HUD box by two points, so GetPoint() reports {BOTTOMLEFT -> parent
--     TOPLEFT} — numbers relative to the BOX. Re-anchoring those to UIParent
--     would fling it to the bottom-left of the screen, so it seeds from screen
--     coordinates instead.
local seeded
local weldFrame = {
  GetPoint = function() return "BOTTOMLEFT", nil, "TOPLEFT", 0, -1 end,
}
Nock.EditMode:Nudge({
  frame = weldFrame,
  spec  = {
    label   = "Cast Bar",
    get     = function() return false end,          -- welded, no saved position
    set     = function(pos) seeded = pos end,
    default = function() return false end,
    capture = function()
      return { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", x = 400, y = 700 }
    end,
  },
}, "up", 1)
ok(seeded.x == 400, "capture: screen x used, not the weld's 0")
ok(seeded.y == 701, "capture: screen y used and nudged, not the weld's -1")
ok(seeded.relPoint == "BOTTOMLEFT", "capture: UIParent-relative anchor adopted")

-- 18. Without spec.capture the GetPoint() path still applies, so nothing else
--     changed underneath.
local plain
Nock.EditMode:Nudge({
  frame = { GetPoint = function() return "CENTER", nil, "CENTER", 10, 20 end },
  spec  = { label = "x", get = function() return nil end,
            set = function(pos) plain = pos end, default = function() end },
}, "right", 1)
ok(plain.x == 11 and plain.point == "CENTER", "no capture: GetPoint seeding unchanged")

print(("nudge_test: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
