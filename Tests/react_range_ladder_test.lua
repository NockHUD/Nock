-- Tests/react_range_ladder_test.lua
-- UI/ReactRangeLadder.lua: segment slices on whole device pixels, label
-- clamping, and the painter lighting exactly one segment. Run from the repo root.

local pass, fail = 0, 0
local function ok(c, n) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. n) end end

-- Minimal frame/texture/fontstring fakes: record what the painter does.
local function region()
  local r = { shown = true, points = {} }
  function r:SetTexture() end
  function r:SetVertexColor(a, b, c, d) self.color = { a, b, c, d } end
  function r:SetPoint(...) self.points[#self.points + 1] = { ... } end
  function r:ClearAllPoints() self.points = {} end
  function r:SetSize(w, h) self.w, self.h = w, h end
  function r:SetWidth(w) self.w = w end
  function r:SetHeight(h) self.h = h end
  function r:Show() self.shown = true end
  function r:Hide() self.shown = false end
  function r:SetShown(v) self.shown = v and true or false end
  function r:IsShown() return self.shown end
  function r:SetText(s) self.text = s end
  function r:SetTextColor(a, b, c, d) self.textColor = { a, b, c, d } end
  function r:GetStringWidth() return #(self.text or "") * 5 end
  function r:SetDrawLayer() end
  function r:SetFont(path, size, flags) self.font, self.size, self.flags = path, size, flags; return true end
  function r:SetShadowOffset(x, y) self.shadow = { x, y } end
  function r:SetShadowColor(a, b, c, d) self.shadowColor = { a, b, c, d } end
  function r:SetJustifyH() end
  return r
end
_G.CreateFrame = function()
  local f = region()
  function f:CreateTexture() return region() end
  function f:CreateFontString() return region() end
  function f:SetFrameLevel() end
  function f:GetFrameLevel() return 1 end
  return f
end
local Nock = { UI = { ApplyBackdrop = function() end } }
_G.LibStub = function() return { GetAddon = function() return Nock end } end
local L = dofile("Forever/RangeLadder.lua")
Nock.RangeLadder = L
dofile("UI/ReactRangeLadder.lua")
local RL = Nock.UI.RangeLadder
ok(RL and type(RL.Slices) == "function", "widget module loads")

-- Slices: whole device pixels, contiguous, ending exactly at innerW.
local base = L.Layout(8, 35)
local dev = 1.2   -- 1.2 physical px per unit (the user's Forever UI scale)
local s = RL.Slices(base, 218, dev)
ok(#s == #base, "one slice per segment")
local contiguous, whole = true, true
for i = 1, #s do
  local px0, px1 = s[i].x * dev, (s[i].x + s[i].w) * dev
  if math.abs(px0 - math.floor(px0 + 0.5)) > 1e-6 or math.abs(px1 - math.floor(px1 + 0.5)) > 1e-6 then whole = false end
  if i > 1 and math.abs(s[i].x - (s[i - 1].x + s[i - 1].w)) > 1e-9 then contiguous = false end
end
ok(whole, "every seam on a whole device pixel")
ok(contiguous and s[1].x == 0, "slices are contiguous from 0")
ok(math.abs((s[#s].x + s[#s].w) * dev - math.floor(218 * dev + 0.5)) < 1e-6, "last slice ends at the inner width")
local wmin, wmax = math.huge, 0
for i = 1, #s do wmin = math.min(wmin, s[i].w); wmax = math.max(wmax, s[i].w) end
ok(wmax - wmin <= 1 / dev + 1e-9, "segments are equal width, within one device pixel (user 2026-09-24)")
local again = RL.Slices(base, 218, dev, s)
ok(again == s, "the out table is reused (no allocation on relayout)")

-- Painter: exactly one lit segment, every segment labelled inside itself,
-- nothing lit without a target.
local function makeText() return region() end
local f = RL.Create({}, { makeText = makeText, bg = { 0, 0, 0, 1 }, border = { 0, 0, 0, 1 }, fontSize = 9 })
ok(#f.labels == 10, "every segment label exists before the first layout, so the React font pass reaches them (got " .. #f.labels .. ")")
ok(f.labels[1].font and f.labels[1].font:find("IBMPlexMono%-Medium") and f.labels[1].flags == "" and f.labels[1].size == RL.LABEL_FONT,
   "labels use IBM Plex Mono Medium (picked in the font preview, 2026-09-24), not the React HUD font")
local reactTexts = 0
local f2 = RL.Create({}, { makeText = function() reactTexts = reactTexts + 1; return region() end, bg = { 0, 0, 0, 1 }, border = { 0, 0, 0, 1 } })
ok(reactTexts == 0 and #f2.labels == 10, "labels stay out of the React font roster (the skin pass would re-font them)")
local f3 = RL.Create({}, { bg = { 0, 0, 0, 1 }, border = { 0, 0, 0, 1 }, face = "Fonts\\ARIALN.TTF", size = 11, flags = "OUTLINE" })
ok(f3.labels[1].font == "Fonts\\ARIALN.TTF" and f3.labels[1].size == 11 and f3.labels[1].flags == "OUTLINE", "a font override reaches every label (the font preview)")
RL.Layout(f, base, 220, 14, true, 1, 1)
RL.Layout(f, base, 220, 14, true, 1.2, 1)
ok(f.labels[1].shadow and math.abs(f.labels[1].shadow[1] - RL.SHADOW_PX / 1.2) < 1e-9 and math.abs(f.labels[1].shadow[2] + RL.SHADOW_PX / 1.2) < 1e-9
   and f.labels[1].shadowColor[4] == 1 and RL.SHADOW_PX == 1, "labels carry a 1 device-px black drop shadow, set at layout")
RL.Layout(f, base, 220, 14, true, 1, 1)
local function litCount()
  local n, which = 0, nil
  for i = 1, #base do
    local c = f.segs[i].color
    if c and not (c[1] == RL.OFF[1] and c[2] == RL.OFF[2] and c[3] == RL.OFF[3]) then n = n + 1; which = base[i].key end
  end
  return n, which
end
local function labelAlpha(i) return f.labels[i].textColor and f.labels[i].textColor[4] end
ok(f.labels[1].text == "M" and f.labels[4].text == "25" and f.labels[9].text == "OUT", "each segment carries its own label (detailed: the upper bound)")
local inside = true
for i = 1, #base do
  local pt = f.labels[i].points[1]
  if not (pt and pt[1] == "CENTER" and pt[2] == f.segs[i]) then inside = false end
end
ok(inside, "every label is centred on its own segment")
RL.Paint(f, "25_28", true)
local n, which = litCount()
ok(n == 1 and which == "25_28", "one segment lit: 25-28")
ok(labelAlpha(5) == 1 and labelAlpha(4) == RL.DIM and f.labels[4].shown, "the lit label is bright, the others dim but shown")
ok(f.marker == nil, "no underline marker: the colour and the bright label say it")
RL.Paint(f, "35_40", false)
ok(f.segs[8].color[1] == L.COLORS.red[1], "35-40 out of Auto Shot range paints red")
RL.Paint(f, nil, false)
n = litCount()
ok(n == 0 and labelAlpha(1) == RL.DIM, "no target: nothing lit, every label dim")
-- Labels off: only the lit segment says where the target is.
RL.Layout(f, base, 220, 14, false, 1, 1)
RL.Paint(f, "20_25", true)
local shown = 0
for i = 1, #base do if f.labels[i].shown then shown = shown + 1 end end
ok(shown == 1 and f.labels[4].shown, "labels off: only the lit segment's label shows")
RL.Paint(f, nil, false)
shown = 0
for i = 1, #base do if f.labels[i].shown then shown = shown + 1 end end
ok(shown == 0, "labels off and no target: no labels")
-- Relayout to Hawk Eye 3 (10 segments) re-paints the lit segment.
local he3 = L.Layout(8, 41)
RL.Paint(f, "40_41", true)
RL.Layout(f, he3, 220, 14, true, 1, 1)
RL.Paint(f, "40_41", true)
ok(f.labels[9].text == "41" and labelAlpha(9) == 1 and f.segs[10].shown and f.segs[9].color[1] == L.COLORS.purple[1], "Hawk Eye 3 layout: 40-41 lit")
RL.Layout(f, base, 220, 14, true, 1, 1)
ok(not f.segs[10].shown and not f.labels[10].shown, "back to 9 segments hides the tenth and its label")

-- Compact: the far block lights in the live bracket's colour and says its value.
local cmp = L.Layout(8, 35, true)
RL.Layout(f, cmp, 220, 14, true, 1, 1)
ok(f.labels[4].text == "20-40" and not f.segs[6].shown, "compact: 5 segments, the block reads 20-40")
ok(math.abs(f.segs[1].w - f.segs[4].w) <= 1, "compact: the far block is as wide as the rest")
RL.Paint(f, "25_28", true)
n, which = 0, nil
for i = 1, #cmp do local c = f.segs[i].color; if c and c[1] ~= RL.OFF[1] then n = n + 1; which = cmp[i].key end end
ok(n == 1 and which == "FAR", "compact: 25-28 lights the far block")
ok(f.segs[4].color[1] == L.COLORS.blue[1] and f.labels[4].text == "25-28" and labelAlpha(4) == 1, "the block takes 25-28's colour and label")
RL.Paint(f, "35_40", false)
ok(f.segs[4].color[1] == L.COLORS.red[1] and f.labels[4].text == "35-40", "past Auto Shot inside the block: red, 35-40")
RL.Paint(f, "MELEE", false)
ok(f.labels[4].text == "20-40" and labelAlpha(4) == RL.DIM and f.segs[1].color[1] == L.COLORS.melee[1], "target leaves the block: it reads 20-40 again, dim")
ok(RL.LABEL_FONT >= 10 and RL.DIM == 0.3, "labels 10 pt, unlit at 30%: present but quieter than the lit label (2026-09-24)")
print(("react_range_ladder: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
