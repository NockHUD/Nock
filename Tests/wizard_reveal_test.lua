-- Tests/wizard_reveal_test.lua
-- The guided wizard's three readings in Core/State.lua: WizardHides (a frame's
-- step not reached yet), IsLockedFor (editable only on the current step) and
-- EditPreview (held open while unlocked AND revealed).
-- Run from the repo root: luajit Tests/wizard_reveal_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end

local addon = { Constants = {}, state = {} }
local module
function addon:NewModule(name) module = { name = name }; return module end
_G.LibStub = function(name, silent)
  if name == "AceAddon-3.0" then return { GetAddon = function() return addon end } end
  if silent then return nil end
  return {}
end
dofile("Core/Constants.lua")
dofile("Core/State.lua")
local Nock = addon
local locked = true
function Nock.IsLocked() return locked end

local demo = Nock.state.demo
ok(demo.guided == false and demo.revealed == false and demo.live == false, "demo carries the three guided fields, off")

-- not guided: nothing hides, everything editable while unlocked
ok(Nock.WizardHides("hud") == false, "not guided: nothing hides")
ok(Nock.IsLockedFor("hud") == true, "locked: not editable")
locked = false
ok(Nock.IsLockedFor("hud") == false, "unlocked, not guided: editable")
ok(Nock.EditPreview("hud") == true, "unlocked, not guided: preview held")

-- guided, page reveals hud only
demo.guided = true
demo.revealed = { hud = true }
demo.live = { hud = true }
ok(Nock.WizardHides("hud") == false and Nock.WizardHides("warnings") == true, "guided: unrevealed frames hide")
ok(Nock.IsLockedFor("hud") == false and Nock.IsLockedFor("warnings") == true, "guided: only live keys editable")
ok(Nock.EditPreview("warnings") == false, "guided: an unrevealed frame holds no preview")

-- a later page: hud revealed but not live
demo.revealed = { hud = true, warnings = true }
demo.live = { warnings = true }
ok(Nock.WizardHides("hud") == false, "earlier step's frame stays revealed")
ok(Nock.IsLockedFor("hud") == true, "earlier step's frame is not editable")
ok(Nock.EditPreview("hud") == false, "earlier step's frame drops its preview (only self-showing frames stay)")
ok(Nock.EditPreview("warnings") == true, "the live step's frame holds its preview")

-- finish: the star
demo.revealed = { ["*"] = true }
demo.live = { ["*"] = true }
ok(Nock.WizardHides("slammer") == false and Nock.IsLockedFor("slammer") == false, "'*' reveals and unlocks every key")

-- locked wins over live
locked = true
ok(Nock.IsLockedFor("warnings") == true and Nock.EditPreview("warnings") == false, "locked: nothing editable, no preview")

-- nil key (a registration without one) is never hidden, edits like the bare lock
locked = false
ok(Nock.WizardHides(nil) == false and Nock.IsLockedFor(nil) == false, "nil key: ungated")

-- Edit focus: one key singled out, the wizard's sets outranked
demo.guided = false; demo.revealed = false; demo.live = false
locked = false
Nock.state.editFocus = "helpers"
ok(Nock.WizardHides("hud") == true and Nock.WizardHides("helpers") == false, "focus: every other keyed frame hides")
ok(Nock.IsLockedFor("hud") == true and Nock.IsLockedFor("helpers") == false, "focus: only the focused frame is editable")
ok(Nock.EditPreview("helpers") == true and Nock.EditPreview("hud") == false, "focus: preview follows the focus")
ok(Nock.IsLockedFor("hud", true) == false, "ignoreFocus: the element list still sees every row")
demo.guided = true; demo.revealed = { hud = true }; demo.live = { hud = true }
ok(Nock.WizardHides("hud") == true and Nock.WizardHides("helpers") == false, "focus outranks the wizard's sets")
ok(Nock.IsLockedFor("hud", true) == false and Nock.IsLockedFor("helpers", true) == true, "ignoreFocus: the wizard's reading alone")
Nock.state.editFocus = false
ok(Nock.WizardHides("helpers") == true, "focus cleared: the wizard's sets rule again")
ok(Nock.WizardHides(nil) == false, "nil key: still ungated")

print(string.format("%d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
