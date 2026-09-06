-- Tests/options_validate_test.lua
-- The real AceConfigRegistry validator accepts the built options table (it re-validates after every NotifyChange; an unknown node key blanks the settings window).
local pass, fail = 0, 0
local function ok(c, n) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. n) end end
local Nock, W, root = dofile("Tests/lib/options_harness.lua")()
ok(type(root) == "table" and root.type == "group", "harness registered the table")

-- Swap the stub LibStub for the real one and load the registry with its dependency.
_G.LibStub = nil
_G.geterrorhandler = function() return function(err) print("callback error: " .. tostring(err)) end end
dofile("Libs/LibStub/LibStub.lua")
dofile("Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua")
dofile("Libs/AceConfig-3.0/AceConfigRegistry-3.0/AceConfigRegistry-3.0.lua")
local reg = LibStub("AceConfigRegistry-3.0")
ok(type(reg.ValidateOptionsTable) == "function", "real AceConfigRegistry loaded")
local okv, err = pcall(reg.ValidateOptionsTable, reg, root, "Nock")
ok(okv, "options table validates: " .. tostring(err))

-- The tags never touch the nodes, so a second validation after Apply still passes.
Nock.OptionsAdvanced.Apply(root)
okv, err = pcall(reg.ValidateOptionsTable, reg, root, "Nock")
ok(okv, "options table still validates after OptionsAdvanced.Apply: " .. tostring(err))
print(("options_validate_test: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
