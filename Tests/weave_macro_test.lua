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
local DOWN    = "/use Snowball\n/stopcasting\n/cast Raptor Strike\n/startattack"
local UP      = "/cast [target=pettarget,exists] Kill Command\n/cast !Auto Shot"
local BARE    = "/stopcasting\n/cast Raptor Strike\n/startattack"

Nock.Constants = {
  WEAVE_BIND_MACRO_DOWN    = DOWN,
  WEAVE_BIND_MACRO_UP      = UP,
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

local gated = WM.WithGate(DOWN, "shirt", "off")
ok(gated == "/use [noequipped:Shirt] Snowball\n" .. BARE,
   "WithGate: wraps the poke in [noequipped:Shirt]")
local g, dir = WM.GateOf(gated)
ok(g == "shirt" and dir == "off", "GateOf: reads shirt/off back")

local worn = WM.WithGate(DOWN, "tabard", "on")
ok(worn == "/use [equipped:Tabard] Snowball\n" .. BARE,
   "WithGate: the 'on' direction writes [equipped:Tabard]")
g, dir = WM.GateOf(worn)
ok(g == "tabard" and dir == "on", "GateOf: reads tabard/on back")

ok(WM.WithGate(gated, "shirt", "off") == gated, "WithGate: idempotent")
ok(WM.WithGate(gated, "tabard", "on") == worn, "WithGate: replaces an existing gate")
ok(WM.WithoutGate(gated) == DOWN, "WithoutGate: back to the plain poke")
ok(WM.WithoutGate(DOWN) == DOWN, "WithoutGate: idempotent")

-- The bracket belongs to the poke and nothing else: a gate must never disarm
-- Raptor Strike or /startattack.
ok(not gated:find("/cast %[", 1), "WithGate: leaves /cast alone")
ok(gated:find("/startattack", 1, true) and not gated:find("startattack %[", 1),
   "WithGate: leaves /startattack alone")

-- Nothing to wrap: a body with no poke is returned untouched.
ok(WM.WithGate(BARE, "shirt", "off") == BARE, "WithGate: no-op without a poke")
ok(WM.GateOf(BARE) == nil, "GateOf: nil without a poke")

-- Removing the poke takes its gate with it.
ok(WM.WithoutSnowball(gated) == BARE, "WithoutSnowball: a gated line goes whole")
-- ...and re-adding it comes back ungated, so the extras page can't show a gate
-- that no longer exists in the text.
ok(WM.WithSnowball(WM.WithoutSnowball(gated)) == DOWN,
   "WithSnowball: re-added ungated after a gated line was dropped")

--------------------------------------------------------------------------------
-- 3. The movement-pad step-out (moved here from Modules/Onboarding.lua)
--------------------------------------------------------------------------------
ok(WM.HasMovePad(clever), "HasMovePad: sees the line")
ok(not WM.HasMovePad(DOWN), "HasMovePad: absent from the shipped body")
ok(WM.WithMovePad(DOWN) == DOWN .. "\n" .. MOVEPAD, "WithMovePad: appends, never prepends")
ok(WM.WithMovePad(WM.WithMovePad(DOWN)) == DOWN .. "\n" .. MOVEPAD, "WithMovePad: idempotent")
ok(WM.WithMovePad("") == MOVEPAD, "WithMovePad: an empty body becomes just the step-out")
ok(WM.WithoutMovePad(DOWN .. "\n" .. MOVEPAD) == DOWN, "WithoutMovePad: strips it")
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
ok(not WM.HasRearm(UP) and WM.HasRearm(UP .. "\n" .. REARM_ON) and WM.HasRearm("/startattack"), "HasRearm: the plain and the gated line, not the shipped release body")
ok(WM.WithRearm(UP, "shirt", "on") == UP .. "\n" .. REARM_ON, "WithRearm: appended last, gated worn")
ok(WM.WithRearm(UP .. "\n" .. REARM_ON, "tabard", "off") == UP .. "\n/startattack [noequipped:Tabard]", "WithRearm: rewrites the line in place")
ok(WM.WithRearm(UP) == UP .. "\n/startattack", "WithRearm: no garment, the plain command")
ok(WM.WithoutRearm(UP .. "\n" .. REARM_ON) == UP and WM.WithoutRearm(UP) == UP, "WithoutRearm strips only the re-arm")
ok(WM.WithoutRearm(DOWN) == (DOWN:gsub("\n/startattack", "")), "WithoutRearm on the press body strips its /startattack too (IsNockAuthored guards that)")
local g1, d1 = WM.RearmGateOf(UP .. "\n" .. REARM_ON)
ok(g1 == "shirt" and d1 == "on", "RearmGateOf reads the bracket")
ok(WM.SyncRearm(UP, "/use [noequipped:Shirt] Snowball\n" .. BARE) == UP .. "\n" .. REARM_ON, "SyncRearm: poke off-while-worn -> re-arm while worn")
ok(WM.SyncRearm(UP, "/use [equipped:Tabard] Snowball\n" .. BARE) == UP .. "\n/startattack [noequipped:Tabard]", "SyncRearm: the inverse follows garment and direction")
ok(WM.SyncRearm(UP .. "\n" .. REARM_ON, DOWN) == UP, "SyncRearm: an ungated poke drops the re-arm")
ok(WM.IsNockAuthored(UP .. "\n" .. REARM_ON, UP) and WM.IsNockAuthored(UP .. "\n" .. MOVEPAD .. "\n" .. REARM_ON, UP), "IsNockAuthored: a stock release body with the re-arm (and MovePad)")
ok(not WM.IsNockAuthored("/cast !Auto Shot\n" .. REARM_ON, UP), "IsNockAuthored: a hand-written release body with a re-arm is the user's")
ok(WM.IsNockAuthored(DOWN, DOWN) and not WM.IsNockAuthored(BARE:gsub("\n/startattack", ""), DOWN), "IsNockAuthored: the press body's own /startattack is part of the stock text")
local prof = { weaveBindMacroDown = "/use [noequipped:Shirt] Snowball\n" .. BARE, weaveBindMacroUp = UP }
ok(WM.SyncRearmIfStock(prof, UP) == true and prof.weaveBindMacroUp == UP .. "\n" .. REARM_ON, "SyncRearmIfStock: a stock release body gains the re-arm")
ok(WM.SyncRearmIfStock(prof, UP) == false, "...and is left alone once in step")
prof.weaveBindMacroDown = DOWN
ok(WM.SyncRearmIfStock(prof, UP) == true and prof.weaveBindMacroUp == UP, "...the gate off takes it away again")
prof.weaveBindMacroDown, prof.weaveBindMacroUp = "/use [noequipped:Shirt] Snowball\n" .. BARE, "/cast !Auto Shot\n/say hi"
ok(WM.SyncRearmIfStock(prof, UP) == false and prof.weaveBindMacroUp == "/cast !Auto Shot\n/say hi", "SyncRearmIfStock: the user's own release body is never touched")
prof.weaveBindMacroUp = ""
ok(WM.SyncRearmIfStock(prof, UP) == false and prof.weaveBindMacroUp == "", "SyncRearmIfStock: an emptied (Natty) release body stays empty")
-- A body typed in the options box: trailing newline, CRLF, trailing blanks.
ok(WM.IsNockAuthored(UP .. "\n", UP) and WM.IsNockAuthored(UP:gsub("\n", "\r\n") .. "\r\n/startattack [equipped:Shirt]\r\n", UP) and WM.IsNockAuthored(UP .. "  \n" .. REARM_ON .. "\n\n", UP),
   "IsNockAuthored: a trailing newline, CRLF or trailing blanks are still the stock body")
prof.weaveBindMacroDown, prof.weaveBindMacroUp = "/use [noequipped:Tabard] Snowball\n" .. BARE, UP .. "\n" .. REARM_ON .. "\n"
ok(WM.SyncRearmIfStock(prof, UP) == true and prof.weaveBindMacroUp == UP .. "\n/startattack [equipped:Tabard]", "SyncRearmIfStock: ...and the re-arm follows the gate on such a body")

-- The garment and direction switches on EVERY bracket of a body (the user's
-- own three-line gate: poke + /startattack on press, /startattack on release).
local MY_DOWN = "/use [noequipped:Shirt] Snowball\n/click MovePadBackward\n/use Raptor Strike\n/use [@pettarget,exists,harm,nodead] Kill Command\n/startattack [noequipped:Shirt]"
local MY_UP   = "/startattack [equipped:Shirt]\n/click MovePadBackward\n/use [@pettarget,exists,harm,nodead] Kill Command\n/use [exists,harm,nodead] !Auto Shot"
ok(WM.WithGarment(MY_DOWN, "tabard") == MY_DOWN:gsub("Shirt", "Tabard") and WM.WithGarment(MY_UP, "tabard") == MY_UP:gsub("Shirt", "Tabard"),
   "WithGarment: every garment bracket follows, polarity kept, other brackets untouched")
ok(WM.InvertGates(MY_DOWN) == "/use [equipped:Shirt] Snowball\n/click MovePadBackward\n/use Raptor Strike\n/use [@pettarget,exists,harm,nodead] Kill Command\n/startattack [equipped:Shirt]"
   and WM.InvertGates(MY_UP) == "/startattack [noequipped:Shirt]\n/click MovePadBackward\n/use [@pettarget,exists,harm,nodead] Kill Command\n/use [exists,harm,nodead] !Auto Shot",
   "InvertGates: every garment bracket flips, line for line")
ok(WM.WithGarment(UP, "tabard") == UP and WM.InvertGates(DOWN) == DOWN, "...and a body with no garment bracket is untouched")
ok(WM.WithGarment(MY_DOWN, "hat") == MY_DOWN, "WithGarment: an unknown garment changes nothing")

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
