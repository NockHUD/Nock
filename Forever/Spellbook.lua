-- Forever/Spellbook.lua
-- The character's spellbook as a name -> spellID map (ranks are separate spells on Forever, so callers match by name).

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")

-- name -> spellID for every spell in the character's spellbook; nil
-- without the API (the caller treats that as "cannot tell").
function Nock.ForeverSpellbookNames()
  local SB, E = _G.C_SpellBook, _G.Enum
  if not (SB and SB.GetNumSpellBookSkillLines and SB.GetSpellBookItemInfo and E and E.SpellBookSpellBank) then return nil end
  local names = {}
  local bank = E.SpellBookSpellBank.Player
  local okn, lines = pcall(SB.GetNumSpellBookSkillLines)
  if not okn or type(lines) ~= "number" then return names end
  for line = 1, lines do
    local oki, info = pcall(SB.GetSpellBookSkillLineInfo, line)
    if oki and type(info) == "table" and info.itemIndexOffset and info.numSpellBookItems then
      for slot = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
        local okb, item = pcall(SB.GetSpellBookItemInfo, slot, bank)
        local n = okb and type(item) == "table" and Nock.Flavor.Plain(item.name) or nil
        local id = okb and type(item) == "table" and Nock.Flavor.Plain(item.spellID) or nil
        if type(n) == "string" then names[n] = (type(id) == "number" and id) or names[n] or true end
      end
    end
  end
  return names
end
