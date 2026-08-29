-- Core/WeaveMacro.lua
-- Pure text surgery on the weave-bind macro bodies: add or remove the Snowball
-- poke, its shirt/tabard gate, and the movement-pad step-out.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")

-- The wizard page and the options builder both edit the SAME stored strings.
-- Keeping every edit here is what stops the two surfaces from drifting into
-- subtly different macro text (the lesson the clip threshold taught): the
-- stored body stays the single source of truth, and both surfaces read their
-- switch positions back out of it, so a hand-edit in the text box is reflected
-- in the wizard and vice versa.
local WM = {}
Nock.WeaveMacro = WM

-- Constants are read at CALL time, not load time: this file sits above
-- Core/Constants.lua in the load order for the wizard's benefit.
local function C() return Nock.Constants or {} end

-- Garment key -> the spelling written into the macro. The resolver in
-- Modules/WeaveBind.lua lowercases before matching, so the case here is purely
-- for the user reading their own macro.
local GARMENTS = { shirt = "Shirt", tabard = "Tabard" }

-- Lines, normalised: CR dropped, trailing blanks trimmed, trailing empty
-- lines dropped. A body typed in the options box (or pasted from Grounded)
-- can end in a newline or carry CRLF, and every comparison here -- above all
-- IsNockAuthored's -- has to read it as the same macro (a trailing newline
-- made a stock release body "the user's" and froze its re-arm on Shirt while
-- the gate flipped to Tabard -- user, 2026-08-27).
local function split(text)
  local out = {}
  if text == nil or text == "" then return out end
  for line in (text .. "\n"):gmatch("(.-)\n") do
    line = line:gsub("\r", ""):gsub("%s+$", "")
    out[#out + 1] = line
  end
  while #out > 0 and out[#out] == "" do out[#out] = nil end
  return out
end

local function join(t) return table.concat(t, "\n") end

-- The item name comes out of the shipped line rather than being spelled again
-- here, so the poke's identity has exactly one definition.
local function pokeLine() return C().WEAVE_BIND_SNOWBALL_LINE or "/use Snowball" end
local function pokeItem() return (pokeLine():gsub("^%s*/use%s+", "")) end

-- A /use line naming the poke item. Merely mentioning the word elsewhere
-- (a /say, a comment) is not the poke and must survive every edit.
local function isPoke(line)
  return line:match("^%s*/use%s") ~= nil and line:find(pokeItem(), 1, true) ~= nil
end

-- Rewrite the poke line in place; `build` receives the old line and returns the
-- new one. Bodies without a poke come back untouched.
local function mapPoke(text, build)
  local t = split(text)
  for i = 1, #t do
    if isPoke(t[i]) then
      t[i] = build(t[i])
      return join(t)
    end
  end
  return text
end

--------------------------------------------------------------------------------
-- The Snowball poke
--------------------------------------------------------------------------------

function WM.HasSnowball(text)
  local t = split(text)
  for i = 1, #t do
    if isPoke(t[i]) then return true end
  end
  return false
end

-- Always inserted FIRST: the poke is an off-GCD position re-check, and anything
-- cast ahead of it spends the GCD before the server has agreed where you stand.
function WM.WithSnowball(text)
  if WM.HasSnowball(text) then return text end
  if text == nil or text == "" then return pokeLine() end
  return pokeLine() .. "\n" .. text
end

function WM.WithoutSnowball(text)
  local t, out = split(text), {}
  for i = 1, #t do
    if not isPoke(t[i]) then out[#out + 1] = t[i] end
  end
  return join(out)
end

--------------------------------------------------------------------------------
-- The garment gate
--------------------------------------------------------------------------------
-- The bracket wraps the poke and nothing else. Gating /cast or /startattack
-- would disarm the whole weave whenever the garment was in the wrong state.

local function gateOfLine(line)
  local low = line:lower()
  -- "noequipped" contains "equipped", so the negative form has to be tried
  -- first; the positive pattern anchors on "[" to keep it from matching inside
  -- the negative one.
  local g = low:match("%[%s*noequipped%s*:%s*(%a+)%s*%]")
  if g and GARMENTS[g] then return g, "off" end
  g = low:match("%[%s*equipped%s*:%s*(%a+)%s*%]")
  if g and GARMENTS[g] then return g, "on" end
  return nil
end

-- Returns garment ("shirt"/"tabard"), dir ("off" = fires while removed, the
-- shipped convention; "on" = fires while worn), or nil when the poke is
-- ungated or absent.
function WM.GateOf(text)
  local t = split(text)
  for i = 1, #t do
    if isPoke(t[i]) then return gateOfLine(t[i]) end
  end
  return nil
end

function WM.WithGate(text, garment, dir)
  local name = GARMENTS[garment or ""]
  if not name then return text end
  local prefix = (dir == "on") and "" or "no"
  return mapPoke(text, function()
    return ("/use [%sequipped:%s] %s"):format(prefix, name, pokeItem())
  end)
end

function WM.WithoutGate(text)
  return mapPoke(text, function() return pokeLine() end)
end

-- The garment and direction switches act on EVERY garment bracket of a body
-- (user, 2026-08-27: their own macros gate three lines -- the poke and a
-- /startattack on press, the /startattack on release the other way round --
-- and a flip to Tabard left them on Shirt because "never touch a custom
-- body" blocked it). A flip is the user's explicit choice: it rewrites the
-- brackets it names and nothing else, stock or custom. Polarity is kept by
-- WithGarment and inverted line for line by InvertGates, so the relation
-- between the lines (press one way, release the other) survives a flip.
local function mapBrackets(text, fn)
  local t = split(text)
  for i = 1, #t do
    t[i] = t[i]:gsub("%[(%s*)([Nn]?[Oo]?)([Ee]quipped)(%s*:%s*)(%a+)(%s*)%]", function(sp1, no, eq, colon, g, sp2)
      if not GARMENTS[g:lower()] then return nil end
      local neg = no ~= ""
      local garment, negOut = fn(g:lower(), neg)
      return ("[%s%s%s%s%s%s]"):format(sp1, negOut and "no" or "", eq, colon, GARMENTS[garment], sp2)
    end)
  end
  return join(t)
end

function WM.WithGarment(text, garment)
  if not GARMENTS[garment or ""] then return text end
  return mapBrackets(text, function(_, neg) return garment, neg end)
end

function WM.InvertGates(text)
  return mapBrackets(text, function(g, neg) return g, not neg end)
end

--------------------------------------------------------------------------------
-- The release re-arm: /startattack on the RELEASE body, gated the OTHER way
-- round from the poke (user, 2026-08-27). With the poke gated behind a
-- garment, the state where the poke is off gets `/startattack
-- [equipped:Shirt]` on release instead -- the attack-state re-check the poke
-- used to give. Written and kept in step by SyncRearm from every gate edit,
-- only on a release body Nock authored; an ungated poke has no re-arm.
--------------------------------------------------------------------------------
local REARM_CMD = "/startattack"

local function isRearm(line)
  return line:match("^%s*/startattack%s*$") ~= nil or line:match("^%s*/startattack%s+%[") ~= nil
end

function WM.HasRearm(text)
  local t = split(text)
  for i = 1, #t do if isRearm(t[i]) then return true end end
  return false
end

-- Garment and direction of the re-arm's bracket, like GateOf; nil when
-- absent or ungated.
function WM.RearmGateOf(text)
  local t = split(text)
  for i = 1, #t do if isRearm(t[i]) then return gateOfLine(t[i]) end end
  return nil
end

-- Appended LAST (after the auto re-arm): the release body's own lines keep
-- their order. `garment`/`dir` nil writes the plain command.
function WM.WithRearm(text, garment, dir)
  local name = GARMENTS[garment or ""]
  local line = name and ("%s [%sequipped:%s]"):format(REARM_CMD, (dir == "on") and "" or "no", name) or REARM_CMD
  local t, out, done = split(text), {}, false
  for i = 1, #t do
    if isRearm(t[i]) then
      if not done then out[#out + 1] = line; done = true end
    else
      out[#out + 1] = t[i]
    end
  end
  if not done then out[#out + 1] = line end
  return join(out)
end

function WM.WithoutRearm(text)
  local t, out = split(text), {}
  for i = 1, #t do
    if not isRearm(t[i]) then out[#out + 1] = t[i] end
  end
  return join(out)
end

-- The inverse mechanism: the release body's re-arm follows the press body's
-- gate -- gated poke -> re-arm gated the other way; no gate -> no re-arm.
function WM.SyncRearm(up, down)
  local g, dir = WM.GateOf(down)
  if not g then return WM.WithoutRearm(up) end
  return WM.WithRearm(up, g, (dir == "on") and "off" or "on")
end

-- The same, on a profile, only where it is Nock's to touch: a release body
-- the user wrote (or imported) is left alone; an empty one (Natty) stays
-- empty. Returns true when the body changed. Called from every gate edit
-- (the wizard, the options builder) and once at enable, so a stock body
-- from before the re-arm existed is brought up to date.
function WM.SyncRearmIfStock(p, shippedUp)
  if not p then return false end
  local up, down = p.weaveBindMacroUp or "", p.weaveBindMacroDown or ""
  if up == "" or not WM.IsNockAuthored(up, shippedUp) then return false end
  local new = WM.SyncRearm(up, down)
  if new == up then return false end
  p.weaveBindMacroUp = new
  return true
end

--------------------------------------------------------------------------------
-- The movement-pad step-out
--------------------------------------------------------------------------------

local function movePadLine() return C().WEAVE_BIND_MOVEPAD_LINE or "/click MovePadBackward" end

function WM.HasMovePad(text)
  return (text or ""):find("MovePad", 1, true) ~= nil
end

-- Appended, never prepended: the press body opens with the poke and that line
-- has to stay first.
function WM.WithMovePad(text)
  if text == nil or text == "" then return movePadLine() end
  if WM.HasMovePad(text) then return text end
  return text .. "\n" .. movePadLine()
end

function WM.WithoutMovePad(text)
  local t, out = split(text), {}
  for i = 1, #t do
    if not t[i]:find("MovePad", 1, true) then out[#out + 1] = t[i] end
  end
  return join(out)
end

-- What the weave button runs during a practice drill, out of combat: the
-- simulated lines (poke, Raptor, /startattack, the re-arm) are stripped, but a
-- MovePad step-out is KEPT — a "Clever" weaver's muscle memory is "hold = back
-- out, release = stop", and the drill reads that real footwork. `footwork` is
-- the practiceFootwork setting: key-only mode exists for places with no room
-- to move, so it runs nothing at all.
function WM.PracticeBody(text, footwork)
  if footwork ~= "move" then return "" end
  if not WM.HasMovePad(text) then return "" end
  return movePadLine()
end

--------------------------------------------------------------------------------
-- Authorship
--------------------------------------------------------------------------------
-- True when the stored body is one Nock itself produced: empty, the shipped
-- default, or the shipped default carrying any combination of the switches the
-- wizard and the options builder offer. Anything else is the user's own writing
-- and must survive the wizard untouched.
function WM.IsNockAuthored(text, shipped)
  if text == nil or text == "" then return true end
  -- Through split/join once, so a trailing newline or CRLF compares equal.
  local n = WM.WithoutGate(WM.WithoutMovePad(join(split(text))))
  if n == shipped or n == WM.WithoutSnowball(shipped) then return true end
  -- The release re-arm (a shipped body never carries one; the press body's
  -- own /startattack is part of `shipped` and stays).
  return WM.WithoutRearm(n) == shipped
end

return WM
