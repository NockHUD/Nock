-- Tests/forever_defaults_test.lua
-- Config/Defaults.lua: the Forever-only default overrides apply with the
-- Forever flag and never without it.
-- Run from the repo root: luajit Tests/forever_defaults_test.lua
local pass, fail = 0, 0
local function ok(c, n) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. n) end end
local function load(forever)
  local Nock = { Flavor = { forever = forever }, Constants = setmetatable({}, { __index = function(t, k) local v = {}; rawset(t, k, v); return v end }) }
  _G.LibStub = function() return { GetAddon = function() return Nock end } end
  dofile("Config/Defaults.lua")
  return Nock.Defaults.profile
end
local tbc = load(false)
ok(tbc.warningLabelFont == "Friz Quadrata TT" and tbc.warningLabelStyle == "THICKOUTLINE", "TBC: the stock warning label font")
local fv = load(true)
ok(fv.warningLabelFont == "Nock Lemon Milk Bold" and fv.warningLabelStyle == "THICKOUTLINE", "Forever: LEMON MILK Bold for the warning labels")
ok(fv.reactFont == "Nock Lemon Milk Bold" and tbc.reactFont == "", "Forever: LEMON MILK Bold for the HUD numbers and labels; TBC keeps the reference face")
-- The Forever HUD baseline (user, 2026-09-23): Solid bars, Lemon Milk Bold at 8
-- with the outline and a shadow, thinner melee bar, taller range and cast
-- bars, both corner icons on. TBC keeps every reference value.
ok(fv.reactBarTexture == "Solid" and fv.reactFontSize == 8 and fv.reactFontStyle == "OUTLINE" and fv.reactFontShadow == true and fv.reactTextOffsetY == 0 and fv.reactTextOffsetX == 1, "Forever: Solid, 8 px, outline + shadow, countdowns nudged 1 px right")
ok(fv.reactAutoH == 14 and fv.reactMeleeH == 8 and fv.reactRangeH == 14 and fv.reactManaH == 12 and fv.reactCastH == 17, "Forever: bar heights 14 / 8 / 14 / 12 / 17")
ok(fv.reactCornerIconSize == 42 and fv.reactCornerIconX == 30 and fv.reactCornerIconY == 50, "Forever: corner icons 42 / 30 / 50")
ok(fv.reactShowAspectIcon == true and fv.reactShowMarkIcon == true, "Forever: aspect and Hunter's Mark corner icons on")
ok(fv.reactCdWholeSeconds == true and tbc.reactCdWholeSeconds == false, "Forever: whole-second cooldown countdowns; TBC keeps the tenths")
ok(fv.reactTickWindupWidth == 2 and tbc.reactTickWindupWidth == 1, "Forever: spell-queue mark 2 px; TBC the reference 1")
ok(fv.cueDeadZoneGate == "raid" and fv.cueMeleeGate == "raid" and fv.cueInRangeGate == "raid" and fv.cueOutOfRangeGate == "raid", "Forever: every range cue gated Raid")
ok(fv.reactCdFontSize == 14 and tbc.reactCdFontSize == 10, "Forever: cooldown grid text at 14; TBC the reference 10")
ok(tbc.reactBarTexture == "" and tbc.reactFontSize == 9 and tbc.reactFontShadow == false and tbc.reactMeleeH == 12 and tbc.reactRangeH == 12 and tbc.reactCastH == 16 and tbc.reactShowAspectIcon == false and tbc.reactShowMarkIcon == false, "TBC: the reference skin untouched")
ok(fv.warnPetDeadEnabled == true and fv.warnPetMissingEnabled == true and fv.warnPetUnhappyEnabled == true and fv.warnNotAttackingEnabled == true and fv.warnNotInRangeEnabled == true, "Forever warning toggles default on")
print(("forever_defaults: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
