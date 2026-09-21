-- Forever/Spells.lua
-- Spell IDs Nock uses on WoW Forever. Only what M1 needs; grown by the
-- `/nock probe spells` spellbook dump, never copied from the TBC table.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")

Nock.Spells = {
  AUTO_SHOT = 75,      -- same ID on every client
  -- GCD probe: an instant on the GCD with no cooldown of its own. Serpent Sting
  -- rank 1 (vanilla IDs carry over: Raptor Strike 2973 seen in the 2026-09-21
  -- probe). Blizzard's whitelisted GCD spell 61304 returns no cooldown data on
  -- this client, so it is not usable here.
  GCD_PROBE = 1978,
}
