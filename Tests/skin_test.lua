-- Tests/skin_test.lua
-- The practice workbench skin (UI/Skin.lua) under the frame stub: the tokens
-- the palette page fixed, the font trio's files on disk, the icon atlas's
-- names, and the helpers painting what they are asked to.
-- Run from the repo root: luajit Tests/skin_test.lua
package.path = "./?.lua;./Tests/?.lua;" .. package.path
local pass, fail = 0, 0
local function ok(cond, name) if cond then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. name) end end
local Stub = dofile("Tests/lib/frame_stub.lua")

Nock = { Constants = { FONT = { PATH = "Fonts\\FRIZQT__.TTF" } } }
local registered = {}
_G.LibStub = function(lib, silent)
  return { Register = function(_, kind, name, path) registered[#registered + 1] = { kind, name, path } end }
end
_G.CreateFrame = Stub.CreateFrame

dofile("UI/IconAtlas.lua")
local Skin = dofile("UI/Skin.lua")

-- 1. tokens
local function hex(c) return ("%02x%02x%02x"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5)) end
ok(hex(Skin.COLORS.ground) == "000000", "ground is pure black")
ok(hex(Skin.COLORS.accent) == "abd473", "the accent is the hunter's green")
ok(hex(Skin.COLORS.good) == hex(Skin.COLORS.accent), "good IS the accent")
ok(hex(Skin.COLORS.wait) == "d9b866" and hex(Skin.COLORS.bad) == "ff5c5c", "wait and fault unchanged")
ok(hex(Skin.COLORS.steady) == "59a6ff" and hex(Skin.COLORS.multi) == "ff9933" and hex(Skin.COLORS.arcane) == "cc66ff", "the abilities' colours are the stage's")
local r, g, b = Skin.Color("no-such-token")
ok(hex({ r, g, b }) == hex(Skin.COLORS.ink), "an unknown token paints ink, never nil")

-- 2. fonts: registered with LSM, files present
ok(#registered == 7 and registered[1][1] == "font" and registered[1][2]:find("^Nock "), "every face registered under a Nock name")
local warmed = 0
for _ in pairs(Skin.WARMED) do warmed = warmed + 1 end
ok(warmed == 7, "every face is touched at load (a face first used mid-session is blank until reload)")
for role, path in pairs(Skin.FONTS) do
  local rel = path:gsub("^Interface\\AddOns\\Nock\\", ""):gsub("\\", "/")
  local f = io.open(rel, "rb")
  ok(f ~= nil, "font file on disk: " .. rel)
  if f then f:close() end
end
ok(io.open("Media/FONTS-LICENSE.txt", "r") ~= nil, "the fonts' OFL note ships with them")

-- 3. the icon atlas: every rail/control name the shell uses is in it
for _, name in ipairs({ "stage", "lesson", "ladder", "review", "scenarios", "style", "focus", "play", "stop", "close", "gear", "skipstart", "skipend", "replay", "ghost" }) do
  ok(Skin.HasIcon(name), "atlas holds '" .. name .. "'")
end
ok(not Skin.HasIcon("no-such-icon"), "...and not a made-up one")
ok(io.open(Nock.IconAtlas.texture:gsub("^Interface\\AddOns\\Nock\\", ""):gsub("\\", "/") .. ".tga", "rb") ~= nil, "the atlas texture is on disk")

-- 4. helpers paint through the stub
local f = Stub.CreateFrame("Frame")
local tex = f:CreateTexture()
ok(Skin.Icon(tex, "ladder", "accent") == true, "Skin.Icon paints a known icon")
ok(tex._tex == (Nock.IconAtlas.files and Nock.IconAtlas.files.ladder) or tex._tex == Nock.IconAtlas.texture, "...from the icon's own file (or the sheet)")
ok(io.open("Media/Icons/ladder.tga", "rb") ~= nil, "the per-icon TGA is on disk")
ok(Skin.Icon(tex, "nope") == false, "...and refuses an unknown one")
Skin.Logo(tex, "mark64")
ok(tex._tex == Skin.LOGOS.mark64, "Skin.Logo picks the mark")
Skin.Surface(f, "surface", "line")
ok(f.skinFill ~= nil and f.skinLine ~= nil and #f.skinLine == 4, "Skin.Surface builds one fill and four hairlines")
Skin.Surface(f, "ground")
ok(f.skinLine[1]._shown == false, "...and hides the lines when none is asked for")

-- 5. buttons and chips (the toolbar's vocabulary)
local b = Skin.Button(f, "Start", "primary")
ok(b.text and b.text:GetText() == "Start" and b.kind == "primary" and b.skinFill ~= nil, "a primary button carries its label on an accent fill")
ok((b._w or 0) >= 40, "...sized to the label")
Skin.ButtonKind(b, "danger")
ok(b.kind == "danger", "ButtonKind restyles in place")
Skin.SetButtonText(b, "STOP", 64)
ok(b.text:GetText() == "STOP" and b._w == 64, "SetButtonText writes the label and a fixed width")
local c = Skin.Chip(f)
Skin.SetChip(c, "READY", "accent", "accentInk")
ok(c.text:GetText() == "READY" and c._h == Skin.CHIP_H and (c._w or 0) > 20, "a chip takes its text and sizes to it")
-- pixel-exact icon size: the 32 px cell over the effective scale
local host = Stub.CreateFrame("Frame"); host._effScale = 0.8; host.GetScale = function() return 0.8 end
local t2 = host:CreateTexture(); t2._parent = host
ok(math.abs(Skin.IconSize(t2, 24) - 40) < 1e-9, "IconSize: a 24 px glyph at scale 0.8 is 40 units (32 screen px)")
local fs = f:CreateFontString()
ok(Skin.Font(fs, "mono", 11) ~= nil, "Skin.Font sets a font")

print(("skin: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
