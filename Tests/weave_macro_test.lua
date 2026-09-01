-- Tests/weave_macro_test.lua
-- Standalone LuaJIT tests for Core/WeaveMacro.lua: the pure text surgery the
-- wizard and the options builder share when they add or remove the Snowball
-- poke, its garment gate and the movement-pad step-out.
-- Run from the repo root: luajit Tests/weave_macro_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end

-- Minimal surface: WeaveMacro touches nothing but the addon table and the
-- macro-text constants.
local Nock = {}
_G.LibStub = function() return { GetAddon = function() return Nock end } end

local SNOW    = "/use Snowball"
local MOVEPAD = "/click MovePadBackward"
local KC_LINE = "/use [@pettarget,exists,harm,nodead] Kill Command"
local DOWN    = SNOW .. "\n/use Raptor Strike\n" .. KC_LINE .. "\n/startattack"
local UP      = KC_LINE .. "\n/use [exists,harm,nodead] !Auto Shot"
local BARE    = "/use Raptor Strike\n" .. KC_LINE .. "\n/startattack"
-- The pre-2026-09 stock pair: still recognised as Nock's so gate edits keep
-- working for profiles that shipped with it.
local LEGACY_DOWN = "/use Snowball\n/stopcasting\n/cast Raptor Strike\n/startattack"
local LEGACY_UP   = "/cast [target=pettarget,exists] Kill Command\n/cast !Auto Shot"

Nock.Constants = {
  WEAVE_BIND_MACRO_DOWN        = DOWN,
  WEAVE_BIND_MACRO_UP          = UP,
  WEAVE_BIND_MACRO_DOWN_LEGACY = LEGACY_DOWN,
  WEAVE_BIND_MACRO_UP_LEGACY   = LEGACY_UP,
  WEAVE_BIND_MOVEPAD_LINE  = MOVEPAD,
  WEAVE_BIND_SNOWBALL_LINE = SNOW,
}

dofile("Core/WeaveMacro.lua")
local WM = Nock.WeaveMacro

ok(type(WM) == "table", "Nock.WeaveMacro is published on the addon table")

--------------------------------------------------------------------------------
-- 1. The Snowball poke
--------------------------------------------------------------------------------
ok(WM.HasSnowball(DOWN), "HasSnowball: the shipped press body carries it")
ok(not WM.HasSnowball(UP), "HasSnowball: the release body does not")
ok(not WM.HasSnowball(""), "HasSnowball: empty body")
ok(not WM.HasSnowball(nil), "HasSnowball: nil body")

ok(WM.WithoutSnowball(DOWN) == BARE, "WithoutSnowball: drops the line, keeps the rest")
ok(WM.WithSnowball(BARE) == DOWN, "WithSnowball: puts it back, first")
ok(WM.WithSnowball(DOWN) == DOWN, "WithSnowball: idempotent")
ok(WM.WithoutSnowball(BARE) == BARE, "WithoutSnowball: idempotent")
ok(WM.WithSnowball("") == SNOW, "WithSnowball: an empty body becomes just the poke")
ok(WM.WithSnowball(nil) == SNOW, "WithSnowball: a nil body becomes just the poke")

-- The poke has to LEAD (it is the off-GCD position re-check; anything cast
-- before it wastes the point), even when the body already ends in a MovePad
-- line the user picked on the previous page.
local clever = BARE .. "\n" .. MOVEPAD
ok(WM.WithSnowball(clever) == SNOW .. "\n" .. clever,
   "WithSnowball: leads the body, MovePad stays last")

-- Only a /use line counts. A body that merely mentions the word must survive.
local mentions = "/cast Raptor Strike\n/say Snowball fight"
ok(not WM.HasSnowball(mentions), "HasSnowball: only a /use line counts")
ok(WM.WithoutSnowball(mentions) == mentions, "WithoutSnowball: leaves other lines alone")

--------------------------------------------------------------------------------
-- 2. The garment gate
--------------------------------------------------------------------------------
ok(WM.GateOf(DOWN) == nil, "GateOf: the shipped body is ungated")

-- The gate covers the poke AND the press body's own /startattack (the user's
-- battle-tested shape, 2026-09-01): with the shirt on, the press neither pokes
-- nor starts the melee auto -- the release's inverse re-arm takes over.
local GATED_BARE = "/use Raptor Strike\n" .. KC_LINE .. "\n/startattack [noequipped:Shirt]"
local gated = WM.WithGate(DOWN, "shirt", "off")
ok(gated == "/use [noequipped:Shirt] Snowball\n" .. GATED_BARE,
   "WithGate: wraps the poke and the press /startattack in [noequipped:Shirt]")
local g, dir = WM.GateOf(gated)
ok(g == "shirt" and dir == "off", "GateOf: reads shirt/off back")

local worn = WM.WithGate(DOWN, "tabard", "on")
ok(worn == "/use [equipped:Tabard] Snowball\n/use Raptor Strike\n" .. KC_LINE .. "\n/startattack [equipped:Tabard]",
   "WithGate: the 'on' direction writes [equipped:Tabard] on both lines")
g, dir = WM.GateOf(worn)
ok(g == "tabard" and dir == "on", "GateOf: reads tabard/on back")

ok(WM.WithGate(gated, "shirt", "off") == gated, "WithGate: idempotent")
ok(WM.WithGate(gated, "tabard", "on") == worn, "WithGate: replaces an existing gate")
ok(WM.WithoutGate(gated) == DOWN, "WithoutGate: back to the plain poke and bare /startattack")
ok(WM.WithoutGate(DOWN) == DOWN, "WithoutGate: idempotent")

-- The bracket belongs to the poke and the /startattack, nothing else: Raptor
-- and the Kill Command line (whose own bracket is part of the stock text)
-- must come through untouched.
ok(gated:find(KC_LINE, 1, true) ~= nil, "WithGate: leaves the Kill Command line alone")
ok(gated:find("/use Raptor Strike", 1, true) ~= nil, "WithGate: leaves Raptor alone")

-- Nothing to wrap: a body with no poke is returned untouched.
ok(WM.WithGate(BARE, "shirt", "off") == BARE, "WithGate: no-op without a poke")
ok(WM.GateOf(BARE) == nil, "GateOf: nil without a poke")

-- Removing the poke takes its gate with it -- the WHOLE gate: the press
-- /startattack loses its bracket too, or a poke-less body would strand a
-- /startattack that never fires with the garment in the wrong state.
ok(WM.WithoutSnowball(gated) == BARE, "WithoutSnowball: a gated line goes whole, the /startattack un-gates")
-- ...and re-adding it comes back ungated, so the extras page can't show a gate
-- that no longer exists in the text.
ok(WM.WithSnowball(WM.WithoutSnowball(gated)) == DOWN,
   "WithSnowball: re-added ungated after a gated line was dropped")

--------------------------------------------------------------------------------
-- 3. The movement-pad step-out (moved here from Modules/Onboarding.lua)
--------------------------------------------------------------------------------
ok(WM.HasMovePad(clever), "HasMovePad: sees the line")
ok(not WM.HasMovePad(DOWN), "HasMovePad: absent from the shipped body")
-- The step-out sits at the TOP of the body (the user's battle-tested
-- position): the backpedal starts/stops as early as possible on each edge.
-- Only the poke (press) or a leading re-arm (release) stay ahead of it.
local CLEVER_DOWN = SNOW .. "\n" .. MOVEPAD .. "\n/use Raptor Strike\n" .. KC_LINE .. "\n/startattack"
ok(WM.WithMovePad(DOWN) == CLEVER_DOWN, "WithMovePad: slots in right after the poke")
ok(WM.WithMovePad(WM.WithMovePad(DOWN)) == CLEVER_DOWN, "WithMovePad: idempotent")
ok(WM.WithMovePad(UP) == MOVEPAD .. "\n" .. UP, "WithMovePad: leads a body with no poke")
ok(WM.WithMovePad("/startattack [equipped:Shirt]\n" .. UP) == "/startattack [equipped:Shirt]\n" .. MOVEPAD .. "\n" .. UP,
   "WithMovePad: a leading re-arm stays ahead of it")
ok(WM.WithMovePad("") == MOVEPAD, "WithMovePad: an empty body becomes just the step-out")
ok(WM.WithoutMovePad(CLEVER_DOWN) == DOWN, "WithoutMovePad: strips it")
ok(WM.WithoutMovePad(DOWN) == DOWN, "WithoutMovePad: idempotent")

--------------------------------------------------------------------------------
-- 4. "Did Nock write this?"
--------------------------------------------------------------------------------
-- The wizard's Default card only rewrites bodies Nock itself produced. Every
-- combination the extras page can generate counts as Nock's, or picking Default
-- after gating the poke would read as "hand-written" and strand the user.
ok(WM.IsNockAuthored(nil, DOWN), "IsNockAuthored: nil")
ok(WM.IsNockAuthored("", DOWN), "IsNockAuthored: empty (Natty)")
ok(WM.IsNockAuthored(DOWN, DOWN), "IsNockAuthored: the shipped body")
ok(WM.IsNockAuthored(DOWN .. "\n" .. MOVEPAD, DOWN), "IsNockAuthored: shipped + MovePad")
ok(WM.IsNockAuthored(BARE, DOWN), "IsNockAuthored: shipped without the poke")
ok(WM.IsNockAuthored(gated, DOWN), "IsNockAuthored: shipped with a gated poke")
ok(WM.IsNockAuthored(gated .. "\n" .. MOVEPAD, DOWN), "IsNockAuthored: gated + MovePad")
ok(WM.IsNockAuthored(UP, UP), "IsNockAuthored: the shipped release body")
ok(WM.IsNockAuthored(UP .. "\n" .. MOVEPAD, UP), "IsNockAuthored: release + MovePad")
-- A release body must NOT qualify by growing a poke it never shipped with.
ok(not WM.IsNockAuthored(SNOW .. "\n" .. UP, UP),
   "IsNockAuthored: a poke added to the release body is the user's doing")
ok(not WM.IsNockAuthored("/cast Mongoose Bite", DOWN), "IsNockAuthored: hand-written body")

--------------------------------------------------------------------------------
-- Practice bodies: what the weave button runs during a drill, out of combat.
-- Only a MovePad step-out survives, and only in real-movement footwork mode.
--------------------------------------------------------------------------------
ok(WM.PracticeBody(DOWN, "move") == "", "PracticeBody: shipped press body runs nothing")
ok(WM.PracticeBody(UP, "move") == "", "PracticeBody: shipped release body runs nothing")
ok(WM.PracticeBody(DOWN .. "\n" .. MOVEPAD, "move") == MOVEPAD, "PracticeBody: press + MovePad keeps the step-out")
ok(WM.PracticeBody(UP .. "\n" .. MOVEPAD, "move") == MOVEPAD, "PracticeBody: release + MovePad keeps the stop")
ok(WM.PracticeBody(DOWN .. "\n" .. MOVEPAD, "key") == "", "PracticeBody: key-only footwork runs nothing")
ok(WM.PracticeBody(nil, "move") == "", "PracticeBody: nil body")
ok(WM.PracticeBody("", "move") == "", "PracticeBody: empty body")

--------------------------------------------------------------------------------
-- The release re-arm (2026-08-27): /startattack on the release body, gated
-- the other way round from the poke, kept in step by SyncRearm.
--------------------------------------------------------------------------------
local REARM_ON  = "/startattack [equipped:Shirt]"
ok(not WM.HasRearm(UP) and WM.HasRearm(REARM_ON .. "\n" .. UP) and WM.HasRearm("/startattack"), "HasRearm: the plain and the gated line, not the shipped release body")
-- The re-arm leads the release body (the user's battle-tested order): the
-- last line wins the attack state, and !Auto Shot has to be it.
ok(WM.WithRearm(UP, "shirt", "on") == REARM_ON .. "\n" .. UP, "WithRearm: prepended first, gated worn")
ok(WM.WithRearm(UP .. "\n" .. REARM_ON, "tabard", "off") == UP .. "\n/startattack [noequipped:Tabard]", "WithRearm: rewrites an existing line in place")
ok(WM.WithRearm(UP) == "/startattack\n" .. UP, "WithRearm: no garment, the plain command")
ok(WM.WithoutRearm(REARM_ON .. "\n" .. UP) == UP and WM.WithoutRearm(UP) == UP, "WithoutRearm strips only the re-arm")
ok(WM.WithoutRearm(DOWN) == (DOWN:gsub("\n/startattack", "")), "WithoutRearm on the press body strips its /startattack too (IsNockAuthored guards that)")
local g1, d1 = WM.RearmGateOf(REARM_ON .. "\n" .. UP)
ok(g1 == "shirt" and d1 == "on", "RearmGateOf reads the bracket")
ok(WM.SyncRearm(UP, "/use [noequipped:Shirt] Snowball\n" .. BARE) == REARM_ON .. "\n" .. UP, "SyncRearm: poke off-while-worn -> re-arm while worn")
ok(WM.SyncRearm(UP, "/use [equipped:Tabard] Snowball\n" .. BARE) == "/startattack [noequipped:Tabard]\n" .. UP, "SyncRearm: the inverse follows garment and direction")
ok(WM.SyncRearm(REARM_ON .. "\n" .. UP, DOWN) == UP, "SyncRearm: an ungated poke drops the re-arm")
ok(WM.IsNockAuthored(REARM_ON .. "\n" .. UP, UP) and WM.IsNockAuthored(REARM_ON .. "\n" .. UP .. "\n" .. MOVEPAD, UP), "IsNockAuthored: a stock release body with the re-arm (and MovePad)")
ok(not WM.IsNockAuthored("/cast !Auto Shot\n" .. REARM_ON, UP), "IsNockAuthored: a hand-written release body with a re-arm is the user's")
ok(WM.IsNockAuthored(DOWN, DOWN) and not WM.IsNockAuthored(BARE:gsub("\n/startattack", ""), DOWN), "IsNockAuthored: the press body's own /startattack is part of the stock text")
local prof = { weaveBindMacroDown = WM.WithGate(DOWN, "shirt", "off"), weaveBindMacroUp = UP }
ok(WM.SyncRearmIfStock(prof, UP) == true and prof.weaveBindMacroUp == REARM_ON .. "\n" .. UP, "SyncRearmIfStock: a stock release body gains the re-arm, first")
ok(WM.SyncRearmIfStock(prof, UP) == false, "...and is left alone once in step")
prof.weaveBindMacroDown = DOWN
ok(WM.SyncRearmIfStock(prof, UP) == true and prof.weaveBindMacroUp == UP, "...the gate off takes it away again")
prof.weaveBindMacroDown, prof.weaveBindMacroUp = WM.WithGate(DOWN, "shirt", "off"), "/cast !Auto Shot\n/say hi"
ok(WM.SyncRearmIfStock(prof, UP) == false and prof.weaveBindMacroUp == "/cast !Auto Shot\n/say hi", "SyncRearmIfStock: the user's own release body is never touched")
prof.weaveBindMacroUp = ""
ok(WM.SyncRearmIfStock(prof, UP) == false and prof.weaveBindMacroUp == "", "SyncRearmIfStock: an emptied (Natty) release body stays empty")
-- A body typed in the options box: trailing newline, CRLF, trailing blanks.
ok(WM.IsNockAuthored(UP .. "\n", UP) and WM.IsNockAuthored((REARM_ON .. "\n" .. UP):gsub("\n", "\r\n") .. "\r\n", UP) and WM.IsNockAuthored(REARM_ON .. "  \n" .. UP .. "\n\n", UP),
   "IsNockAuthored: a trailing newline, CRLF or trailing blanks are still the stock body")
prof.weaveBindMacroDown, prof.weaveBindMacroUp = WM.WithGate(DOWN, "tabard", "off"), UP .. "\n" .. REARM_ON .. "\n"
ok(WM.SyncRearmIfStock(prof, UP) == true and prof.weaveBindMacroUp == UP .. "\n/startattack [equipped:Tabard]", "SyncRearmIfStock: ...and the re-arm follows the gate on such a body, in place")

--------------------------------------------------------------------------------
-- Legacy stock: the pre-2026-09 pair. Recognised as Nock's when the caller
-- names it (third arg), so gate edits and SyncRearm keep working for profiles
-- that shipped with it; without the arg it reads as the user's own writing.
--------------------------------------------------------------------------------
ok(WM.IsNockAuthored(LEGACY_DOWN, DOWN, LEGACY_DOWN), "IsNockAuthored: the legacy press body, via the legacy arg")
ok(WM.IsNockAuthored(LEGACY_DOWN .. "\n" .. MOVEPAD, DOWN, LEGACY_DOWN), "IsNockAuthored: legacy + MovePad")
ok(WM.IsNockAuthored(WM.WithGate(LEGACY_DOWN, "shirt", "off"), DOWN, LEGACY_DOWN), "IsNockAuthored: legacy, gated")
ok(WM.IsNockAuthored(REARM_ON .. "\n" .. LEGACY_UP, UP, LEGACY_UP), "IsNockAuthored: legacy release + re-arm")
ok(not WM.IsNockAuthored(LEGACY_DOWN, DOWN), "IsNockAuthored: without the legacy arg the old body is the user's")
local lprof = { weaveBindMacroDown = WM.WithGate(LEGACY_DOWN, "shirt", "off"), weaveBindMacroUp = LEGACY_UP }
ok(WM.SyncRearmIfStock(lprof, UP, LEGACY_UP) == true and lprof.weaveBindMacroUp == REARM_ON .. "\n" .. LEGACY_UP,
   "SyncRearmIfStock: the legacy release body still follows the gate")

-- The garment and direction switches on EVERY bracket of a body (the user's
-- own three-line gate: poke + /startattack on press, /startattack on release).
local MY_DOWN = "/use [noequipped:Shirt] Snowball\n/click MovePadBackward\n/use Raptor Strike\n/use [@pettarget,exists,harm,nodead] Kill Command\n/startattack [noequipped:Shirt]"
local MY_UP   = "/startattack [equipped:Shirt]\n/click MovePadBackward\n/use [@pettarget,exists,harm,nodead] Kill Command\n/use [exists,harm,nodead] !Auto Shot"
-- The whole point of the 2026-09 rework: gate + Clever on the shipped pair
-- reproduces the author's battle-tested bodies EXACTLY, line for line.
local rdDown = WM.WithMovePad(WM.WithGate(DOWN, "shirt", "off"))
local rdUp   = WM.SyncRearm(WM.WithMovePad(UP), rdDown)
ok(rdDown == MY_DOWN, "round trip: gate + Clever rebuilds the author's press body verbatim")
ok(rdUp == MY_UP, "round trip: ...and the release body verbatim")
ok(WM.WithGarment(MY_DOWN, "tabard") == MY_DOWN:gsub("Shirt", "Tabard") and WM.WithGarment(MY_UP, "tabard") == MY_UP:gsub("Shirt", "Tabard"),
   "WithGarment: every garment bracket follows, polarity kept, other brackets untouched")
ok(WM.InvertGates(MY_DOWN) == "/use [equipped:Shirt] Snowball\n/click MovePadBackward\n/use Raptor Strike\n/use [@pettarget,exists,harm,nodead] Kill Command\n/startattack [equipped:Shirt]"
   and WM.InvertGates(MY_UP) == "/startattack [noequipped:Shirt]\n/click MovePadBackward\n/use [@pettarget,exists,harm,nodead] Kill Command\n/use [exists,harm,nodead] !Auto Shot",
   "InvertGates: every garment bracket flips, line for line")
ok(WM.WithGarment(UP, "tabard") == UP and WM.InvertGates(DOWN) == DOWN, "...and a body with no garment bracket is untouched")
ok(WM.WithGarment(MY_DOWN, "hat") == MY_DOWN, "WithGarment: an unknown garment changes nothing")

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
