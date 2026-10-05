-- Tests/forever_pet_row_test.lua
-- UI/Frame_ReactPetRow.lua: when the row is wanted, and that it asks for a re-stack only on a flip.
-- Run from the repo root: luajit Tests/forever_pet_row_test.lua
local pass, fail = 0, 0
local function ok(c, n) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. n) end end
local now = 100
_G.GetTime = function() return now end
local function stubFrame()
  local f = { shown = false }
  local function nop() end
  setmetatable(f, { __index = function() return nop end })
  f.CreateTexture = function() return stubFrame() end
  f.CreateFontString = function() return stubFrame() end
  f.Show = function(self) self.shown = true end
  f.Hide = function(self) self.shown = false end
  f.IsShown = function(self) return self.shown end
  return f
end
_G.CreateFrame = function() return stubFrame() end
local react, preview = true, false
local Nock = {
  Flavor = { forever = true, Plain = function(v) return v end },
  Constants = { FONT = { PATH = "font" } },
  db = { profile = { reactShowPetRow = true, reactWidth = 220 } },
  UI = setmetatable({
    -- headless: 1 px per unit (PixelScale falls through to the nil stub)
    SeamPx = function(v, s) return math.max(1, math.floor(v * (s or 1) + 0.5)) end,
    EvenPx = function(v, s) local px = math.max(1, math.floor(v * (s or 1) + 0.5)); return px + px % 2 end,
  }, { __index = function() return function() end end }),
  parentFrame = stubFrame(),
}
local sent = 0
local mod
function Nock:NewModule(name) mod = { name = name }
  function mod:RegisterMessage() end
  function mod:SendMessage(m) if m == "NOCK_HUD_RELAYOUT" then sent = sent + 1 end end
  return mod end
_G.LibStub = function() return { GetAddon = function() return Nock end } end
dofile("Core/State.lua")
-- Core/State.lua defines the real HudIsReact / EditPreview: stub them AFTER.
Nock.HudIsReact = function() return react end
Nock.EditPreview = function() return preview end
dofile("Forever/PetLamp.lua")
dofile("UI/Frame_ReactPetRow.lua")
local R = mod
R:OnInitialize()

local W = R.Want
ok(W({ reactShowPetRow = true }, true, true, false) == true, "on + React + lamp: wanted")
ok(W({ reactShowPetRow = false }, true, true, true) == false, "toggle off: never wanted, even previewing")
ok(W({ reactShowPetRow = true }, false, true, true) == false, "not React: never wanted")
ok(W({}, true, true, false) == false, "unset key reads OFF (opt-in)")
ok(W({ reactShowPetRow = true }, true, false, false) == false, "no lamp to show: hidden")
ok(W({ reactShowPetRow = true }, true, false, true) == true, "no pet but edit preview: shown")
ok(R:ContentHeight() == 14, "fixed height: 4 px lamps + label line reserved")

local st = Nock.state
st.pet.exists, st.pet.happiness = true, 3
R:Refresh(st)
ok(R:Wanted() == true and sent == 1, "first show: one relayout")
R:Refresh(st); R:Refresh(st)
ok(sent == 1, "relayout fires only on a flip")
st.pet.dead = true
R:Refresh(st)
ok(R:Wanted() == false and sent == 2, "pet died: hide, one relayout")

-- Crisp geometry: integer lamp widths, strip centred on a whole pixel.
local G = R.Geometry
for _, w in ipairs({ 220, 223, 180, 301 }) do
  local sw, lw, lx = G(w)
  ok(sw % 1 == 0 and (w - sw) % 2 == 0, "strip width integral and centred on a pixel at reactWidth " .. w)
  local sum = 0
  for k = 1, 3 do
    ok(lw[k] % 1 == 0 and lw[k] >= 1, "lamp " .. k .. " integral at " .. w)
    sum = sum + lw[k]
  end
  ok(sum + 4 == sw, "lamps + border + seams fill the strip at " .. w)
  ok(lx[1] == 1 and lx[2] == lx[1] + lw[1] + 1 and lx[3] == lx[2] + lw[2] + 1, "1px seams at " .. w)
  ok(math.abs(sw - 0.25 * w) <= 1, "about 25% wide at " .. w)
end

-- Width and height from the profile (React HUD sliders).
local p = Nock.db.profile
for _, c in ipairs({ { 220, 0.5 }, { 220, 1.0 }, { 100, 0.10 }, { 223, 0.15 } }) do
  local sw, lw = G(c[1], c[2])
  ok((c[1] - sw) % 2 == 0 and lw[1] >= 1 and lw[2] >= 1 and lw[3] >= 1 and sw <= c[1], ("fits and centres at %d x %.2f"):format(c[1], c[2]))
  ok(math.abs(sw - c[2] * c[1]) <= 1 or sw == 7 or sw == 8, ("width follows the fraction at %d x %.2f"):format(c[1], c[2]))
end
p.reactPetRowH = 10
ok(R:ContentHeight() == 20, "row height follows the lamp height (+ label line)")
p.reactPetRowH = 99
ok(R:ContentHeight() == 26, "lamp height clamps at 16")
p.reactPetRowH = 1
ok(R:ContentHeight() == 13, "lamp height clamps at 3")
p.reactPetRowH = nil
ok(R:ContentHeight() == 14, "default 4 px")
p.reactPetRowW = 50
ok(R.WidthFrac(p) == 0.5, "width setting is a percent of the HUD")
p.reactPetRowW = nil
ok(R.WidthFrac(p) == 0.25, "default 25 %")

-- The row scales with the React HUD (reviewer finding #1). HUD.lua has no
-- harness, so pin the two table entries in its source.
local hud = io.open("UI/HUD.lua"):read("*a")
ok(hud:find('ReactPetRow%s*=%s*"reactScale"') ~= nil, "ReactPetRow shares reactScale with the cluster and grid")
ok(hud:find('ReactPetRow%s*=%s*"Pet Happiness"') ~= nil, "ReactPetRow has an edit-mode label")
ok(hud:find('module = "ReactPetRow",[^\n]*seam = true') ~= nil, "welded under the grid: one shared 1px seam, no row gap")

print(("forever_pet_row: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
