-- Tests/forever_spellbook_test.lua
-- Forever/Spellbook.lua: the character's spellbook as a name -> spellID map.
-- Run from the repo root: luajit Tests/forever_spellbook_test.lua
local pass, fail = 0, 0
local function ok(c, n) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. n) end end
local Nock = { Flavor = { Plain = function(v) if v == "SECRET" then return nil end return v end } }
_G.LibStub = function() return { GetAddon = function() return Nock end } end
dofile("Forever/Spellbook.lua")
ok(type(Nock.ForeverSpellbookNames) == "function", "exported")
_G.Enum = { SpellBookSpellBank = { Player = 0 } }
ok(Nock.ForeverSpellbookNames() == nil, "no C_SpellBook: nil (cannot tell)")
local book = { [1] = { name = "Aspect of the Hawk", spellID = 14318 }, [2] = { name = "Aspect of the Monkey", spellID = 13163 }, [3] = { name = "SECRET", spellID = 5 } }
_G.C_SpellBook = {
  GetNumSpellBookSkillLines = function() return 1 end,
  GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = 3 } end,
  GetSpellBookItemInfo = function(slot) return book[slot] end,
}
local n = Nock.ForeverSpellbookNames()
ok(n["Aspect of the Hawk"] == 14318 and n["Aspect of the Monkey"] == 13163, "names map to the rank's own id")
ok(n.SECRET == nil, "a secret name is skipped")
print(("forever_spellbook: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
