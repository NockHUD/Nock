-- Tests/settings_input_commit_test.lua
-- UI/SettingsControls.lua input rows: a single-line box commits on Enter AND
-- when focus leaves it with a changed value (the Add an entry form was filled
-- by clicks and never set its id, 2026-09-24); Escape discards; an unchanged
-- box does not commit on blur. Run from the repo root: luajit Tests/settings_input_commit_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. name) end
end

-- Any-method stub frame: unknown methods are no-ops; scripts, text and the
-- multi-line flag are real. ClearFocus fires OnEditFocusLost like the client.
local function stub()
  local o = { _scripts = {}, _text = "", _multi = false, _h = 0 }
  return setmetatable(o, { __index = function(t, k)
    if type(k) ~= "string" or k:match("^%l") then return nil end   -- fields: absent; methods: CamelCase
    if k == "SetScript" then return function(self, ev, fn) self._scripts[ev] = fn end end
    if k == "SetText" then return function(self, s) self._text = s end end
    if k == "GetText" then return function(self) return self._text end end
    if k == "SetMultiLine" then return function(self, v) self._multi = v end end
    if k == "IsMultiLine" then return function(self) return self._multi end end
    if k == "SetHeight" then return function(self, h) self._h = h end end
    if k == "GetHeight" then return function(self) return self._h end end
    if k == "GetWidth" then return function() return 600 end end
    if k == "ClearFocus" then return function(self) local f = self._scripts.OnEditFocusLost; if f then f(self) end end end
    if k == "CreateFontString" or k == "CreateTexture" then return function() return stub() end end
    return function() end
  end })
end
_G.CreateFrame = function() return stub() end
_G.PlaySound = function() end
_G.UIParent = stub()

local store, sets = {}, 0
local W = {
  Get = function(row) return true, store[row.key] end,
  Set = function(row, v) sets = sets + 1; store[row.key] = v; return true end,
  Validate = function() return true end,
}
local Skin = setmetatable({}, { __index = function() return function() return stub() end end })
local Nock = { UI = {}, Skin = Skin, OptionsWalk = W, Print = function() end }
_G.LibStub = function() return { GetAddon = function() return Nock end } end
dofile("UI/SettingsControls.lua")
local SC = Nock.UI.SettingsControls

local after = 0
local host = { AfterSet = function() after = after + 1 end }
local ctl = SC.Acquire("input", stub())
local row = { key = "addId", type = "input", name = "Spell / Item ID", node = {} }
ctl:Bind(row, host)
local box = ctl.box

-- Typed, then the user clicks the next field: focus leaves with a new value.
box:SetText("19434")
box._scripts.OnEditFocusLost(box)
ok(store.addId == "19434" and sets == 1, "blur with a changed value commits")
ok(after >= 1, "the host refreshes after the commit")

-- Blur again with the same value: nothing to commit.
box._scripts.OnEditFocusLost(box)
ok(sets == 1, "blur with the value unchanged does not commit")

-- Enter commits once (its own ClearFocus blur finds nothing changed).
box:SetText("2643")
box._scripts.OnEnterPressed(box)
ok(store.addId == "2643" and sets == 2, "Enter commits exactly once")

-- Escape discards the edit.
box:SetText("999")
box._scripts.OnEscapePressed(box)
ok(store.addId == "2643" and sets == 2, "Escape discards")

-- A form's LAST field still has focus when its button is clicked: clicking a
-- button does not take keyboard focus in the client, so the box never blurs.
-- The button commits the focused box first and re-reads its own disabled
-- (drawn from the value before the commit), then runs (Your sounds, 2026-09-28).
W.Member = function(node, key)
  local v = node[key]
  if type(v) == "function" then return true, v() end
  return true, v
end
local focused
_G.GetCurrentKeyBoardFocus = function() return focused end
store.addId = ""
local ran = 0
local exec = SC.Acquire("execute", stub())
local execNode = {
  disabled = function() return (store.addId or "") == "" end,
  func = function() ran = ran + 1 end,
}
W.Func = function(r) r.node.func(); return true end
W.ConfirmText = function() return nil end
local execRow = { key = "addBtn", type = "execute", name = "Add", node = execNode, disabled = true }
exec:Bind(execRow, host)
box:SetText("19434")
focused = box
exec.btn._scripts.OnClick(exec.btn)
ok(store.addId == "19434", "clicking the button commits the focused box first")
ok(ran == 1, "the button re-reads disabled after the commit and runs")
-- Nothing focused and still disabled: the click stays refused.
focused = nil
store.addId = ""
execRow.disabled = true
exec.btn._scripts.OnClick(exec.btn)
ok(ran == 1, "a disabled button with no pending edit does not run")

print(("settings_input_commit: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
