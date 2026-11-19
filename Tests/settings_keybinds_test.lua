-- Tests/settings_keybinds_test.lua
-- UI/Settings_KeyBinds.lua: Split takes the editor rows out of a card's
-- lines in the editor's order and leaves everything else for the plain flow.
-- Run from the repo root: luajit Tests/settings_keybinds_test.lua
local pass, fail = 0, 0
local function ok(c, n) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. n) end end

local Nock = { Skin = {}, Settings = {}, OptionsWalk = {}, UI = { SettingsControls = {} } }
_G.LibStub = function() return { GetAddon = function() return Nock end } end
dofile("UI/Settings_KeyBinds.lua")
local V = Nock.KeyBindsView
ok(V and type(V.Split) == "function", "Nock.KeyBindsView.Split exists")

local function row(key) return { key = key } end
local ORDER = { "kbName", "kbKey", "kbConflict", "kbDown", "kbUp", "kbDuplicate", "kbDelete", "kbStatus" }

-- source order scrambled, one unrelated row, one line holding two rows
local lines = {
  { rows = { row("kbStatus") } },
  { rows = { row("other") } },
  { rows = { row("kbUp"), row("kbDown") } },
  { rows = { row("kbKey") } }, { rows = { row("kbName") } }, { rows = { row("kbConflict") } },
  { rows = { row("kbDelete") } }, { rows = { row("kbDuplicate") } },
}
local ed, rest = V.Split(lines)
local got = {}
for i, r in ipairs(ed) do got[i] = r.key end
ok(table.concat(got, ",") == table.concat(ORDER, ","), "editor rows in the editor's order, got " .. table.concat(got, ","))
ok(#rest == 1 and rest[1].rows[1].key == "other", "the unrelated row stays in the flow")

-- empty list: the editor rows are hidden, so absent
local ed2, rest2 = V.Split({ { rows = { row("other") } } })
ok(#ed2 == 0 and #rest2 == 1, "no editor rows: nothing taken")

print(("settings_keybinds: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
