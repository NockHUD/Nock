-- Tests/cooldown_editor_test.lua
-- Core/CooldownEditor.lua: pure row operations and the profile row store.
-- Run from the repo root: luajit Tests/cooldown_editor_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. name) end
end
local function same(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do
    if #a[i] ~= #b[i] then return false end
    for j = 1, #a[i] do if a[i][j] ~= b[i][j] then return false end end
  end
  return true
end

local inCombat = false
_G.InCombatLockdown = function() return inCombat end
local sent = 0
local rebuilt = 0
local Nock = {
  Flavor = { forever = true },
  Constants = { TRACKED_COOLDOWNS = {}, REACT_CD_ROWS = {} },
  db = { profile = { reactCdRows = false, reactCooldownDisabled = {}, cooldownCustom = {} } },
}
function Nock:SendMessage() sent = sent + 1 end
function Nock:GetModule(name) if name == "Cooldowns" then return { RebuildLists = function() rebuilt = rebuilt + 1 end } end end
_G.LibStub = function() return { GetAddon = function() return Nock end } end
dofile("Forever/Spells.lua")
dofile("Forever/CooldownCatalog.lua")
dofile("Core/CooldownEditor.lua")
local E, S = Nock.CooldownEditor, Nock.CooldownRows

-- Find / Add
local base = { { "Arc", "RF" }, { "FD" } }
ok(select(1, E.Find(base, "RF")) == 1 and select(2, E.Find(base, "RF")) == 2, "Find")
local r2, ri, ci = E.Add(base, 2, "Conc")
ok(same(r2, { { "Arc", "RF" }, { "FD", "Conc" } }) and ri == 2 and ci == 2, "Add appends to the row")
ok(same(base, { { "Arc", "RF" }, { "FD" } }), "Add does not mutate its input")
local r3, pri, pci = E.Add(base, 2, "RF")
ok(same(r3, base) and pri == 1 and pci == 2, "Add of a placed key is a no-op returning its position")

-- Move
ok(same(E.Move(base, "Arc", 1, 3), { { "RF", "Arc" }, { "FD" } }), "Move right within a row (index counted with the key in place)")
ok(same(E.Move(base, "RF", 1, 1), { { "RF", "Arc" }, { "FD" } }), "Move left within a row")
ok(same(E.Move(base, "RF", 2, 1), { { "Arc" }, { "RF", "FD" } }), "Move to the front of the other row")
ok(same(E.Move(base, "RF", 2, 99), { { "Arc" }, { "FD", "RF" } }), "Move clamps past the end")
ok(same(E.Move(base, "Nope", 2, 1), base), "Move of a missing key changes nothing")
ok(same(E.Move(base, "Arc", 3, 1), base), "Move to a missing row changes nothing")

-- Remove
ok(same(E.Remove(base, "RF"), { { "Arc" }, { "FD" } }), "Remove")

-- Sanitize: duplicates and unknown keys go; exactly nRows rows come back
local valid = function(k) return k ~= "Bogus" end
ok(same(E.Sanitize({ { "Arc", "Arc", "Bogus" }, { "FD", "Arc" }, { "RF" } }, valid, 2), { { "Arc" }, { "FD" } }),
   "Sanitize drops duplicates, unknown keys and extra rows")
ok(same(E.Sanitize({ { "Arc" } }, valid, 2), { { "Arc" }, {} }), "Sanitize pads missing rows")
ok(same(E.Sanitize("garbage", valid, 2), { {}, {} }), "Sanitize survives a non-table")

-- Migrate
ok(same(E.Migrate({ { "Arc", "RF" }, { "FD" } }, { RF = true }), { { "Arc" }, { "FD" } }), "Migrate removes hidden keys")

-- VisibleToSaved: a hidden (other-race) key sits between visible tiles
local saved = { "Arc", "Elune", "RF", "Meld" }
local visible = { "Arc", "RF" }
ok(E.VisibleToSaved(saved, visible, 1) == 1, "before the first visible tile")
ok(E.VisibleToSaved(saved, visible, 2) == 3, "before RF lands before RF's saved slot, after the hidden Elune")
ok(E.VisibleToSaved(saved, visible, 3) == 4, "past the last visible tile lands right after it")
ok(E.VisibleToSaved({}, {}, 1) == 1, "empty row")

-- Store: validity is catalog-or-custom, NOT "tracked"
ok(S.IsValidKey("Stone"), "a name-only racial stays valid before the spellbook resolves it")
ok(not S.IsValidKey("Bogus"), "an unknown key is invalid")
ok(same(S.Get(), { Nock.Constants.REACT_CD_ROWS[1].keys, Nock.Constants.REACT_CD_ROWS[2].keys }), "Get falls back to the defaults")

ok(S.Set({ { "Arc", "Stone" }, { "FD" } }) == true, "Set out of combat")
ok(same(S.Get(), { { "Arc", "Stone" }, { "FD" } }), "Set persists and keeps name-only racials")
ok(sent >= 1, "Set broadcasts NOCK_VISUALS_CHANGED")
inCombat = true
ok(S.Set({ {}, {} }) == false, "Set is refused in combat")
ok(S.ApplyPack("minimal") == false, "ApplyPack is refused in combat")
inCombat = false

-- Packs and undo
ok(S.ApplyPack("bm") == true and S.CanUndo(), "ApplyPack sets rows and arms undo")
local afterPack = S.Get()
local hasBW = false
for _, k in ipairs(afterPack[1]) do if k == "BW" then hasBW = true end end
ok(hasBW, "a pack keeps a talent the character may not have (greyed, not dropped)")
ok(S.Undo() == true and same(S.Get(), { { "Arc", "Stone" }, { "FD" } }), "Undo restores the rows before the pack")
ok(not S.CanUndo(), "undo is one step")
S.ApplyPack("minimal")
S.Set(E.Remove(S.Get(), "FD"))
ok(not S.CanUndo(), "a later edit clears undo")
S.ApplyPack("bm")
ok(S.CanUndo(), "ApplyPack re-arms undo")
S.ClearUndo()
ok(not S.CanUndo(), "ClearUndo clears the undo slot (settings window close)")

-- Migration (once)
local p = Nock.db.profile
p.reactCdRows, p.reactCdMigrated = false, nil
p.reactCooldownDisabled = { RF = true }
S.MigrateOnce()
local after = S.Get()
local hasRF = false
for _, k in ipairs(after[1]) do if k == "RF" then hasRF = true end end
ok(not hasRF and next(p.reactCooldownDisabled) == nil and p.reactCdMigrated == true, "MigrateOnce folds hidden slots into the rows")
p.reactCooldownDisabled = { Arc = true }
S.MigrateOnce()
ok(p.reactCooldownDisabled.Arc == true, "MigrateOnce runs once")

-- MigrateOnce is type-safe (a garbage row) and sanitizes what it writes
-- (a duplicate key, an unknown key) rather than trusting the input verbatim.
p.reactCdMigrated = nil
p.reactCooldownDisabled = { RF = true }
p.reactCdRows = { { "Arc", "Arc", "Bogus", "RF" }, "garbage" }
local migrateOk = pcall(S.MigrateOnce)
ok(migrateOk, "MigrateOnce doesn't throw on a duplicate key and a garbage row")
ok(same(S.Get(), { { "Arc" }, {} }), "MigrateOnce leaves sanitized, migrated rows")

-- Custom spells
local key = S.AddCustomSpell(1234)
ok(key == "c_spell_1234" and #p.cooldownCustom == 1 and rebuilt == 1, "AddCustomSpell stores a spell record and rebuilds")
ok(S.AddCustomSpell(1234) == "c_spell_1234" and #p.cooldownCustom == 1, "AddCustomSpell is idempotent")
ok(S.IsValidKey("c_spell_1234"), "a custom key is valid")
p.cooldownCustom[#p.cooldownCustom + 1] = { type = "spell", id = 55 }   -- legacy record without a key
ok(S.IsValidKey("c_spell_55"), "a legacy custom record's derived key is valid")

-- DeleteCustom
ok(S.DeleteCustom("Arc") == false, "DeleteCustom refuses a catalog key")
S.Set(E.Add(S.Get(), 1, "c_spell_1234"))
ok(Nock.CooldownEditor.Find(S.Get(), "c_spell_1234") ~= nil, "c_spell_1234 placed for the test")
inCombat = true
ok(S.DeleteCustom("c_spell_1234") == false, "DeleteCustom refuses in combat")
ok(Nock.CooldownEditor.Find(S.Get(), "c_spell_1234") ~= nil, "a refused delete leaves the row alone")
inCombat = false
ok(S.DeleteCustom("c_spell_1234") == true, "DeleteCustom removes a custom spell")
ok(Nock.CooldownEditor.Find(S.Get(), "c_spell_1234") == nil, "the key is gone from the rows")
local stillThere = false
for _, rec in ipairs(p.cooldownCustom) do if rec.id == 1234 then stillThere = true end end
ok(not stillThere, "the record is gone from cooldownCustom")
ok(not S.IsValidKey("c_spell_1234"), "the deleted key is no longer valid")
ok(S.DeleteCustom("c_spell_1234") == false, "DeleteCustom refuses an already-removed key")
ok(rebuilt == 2, "DeleteCustom rebuilds the tracked lists")

S.ApplyPack("minimal")
ok(S.CanUndo(), "undo armed before delete")
ok(S.DeleteCustom("c_spell_55") == true, "DeleteCustom removes the legacy custom record")
ok(not S.CanUndo(), "DeleteCustom clears undo")
ok(rebuilt == 3, "DeleteCustom rebuilds the tracked lists again")

print(("cooldown_editor: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
