-- Tests/react_weave_strip_test.lua
-- UI/ReactWeaveStrip.lua: the pure look per stage and zone, and the painter
-- under the frame stub (diffed, swipes fed on their edges).
-- Run from the repo root: luajit Tests/react_weave_strip_test.lua

local pass, fail = 0, 0
local function ok(c, n) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. n) end end
local function near(a, b) return type(a) == "number" and math.abs(a - b) < 1e-6 end

local Stub = dofile("Tests/lib/frame_stub.lua")
_G.CreateFrame = Stub.CreateFrame
local Nock = {
  UI = {
    ApplyBackdrop = function() end,
    FlashMix = function(e, d) local m = 1 - e / d; if m < 0 then return 0 elseif m > 1 then return 1 end; return m end,
  },
  API = {
    SpellIcon = function(id) return "icon:" .. tostring(id) end,
    SpellCooldownDuration = function(id) return { id = id } end,
  },
  Spells = { AUTO_SHOT = 75, RAPTOR_STRIKE = 2973 },
  Flavor = { forever = true },
}
_G.LibStub = function() return { GetAddon = function() return Nock end } end
dofile("UI/ReactWeaveStrip.lua")
local WS = Nock.UI.WeaveStrip
ok(WS and type(WS.Look) == "function", "Nock.UI.WeaveStrip exists")

-- Look: pure.
local function S(zone, stage, extra)
  local st = { target = { exists = true, alive = true, friendly = false, rangeState = zone },
               weave = { stage = stage, glide = 0, legStale = false }, ranged = {}, cooldowns = {} }
  for k, v in pairs(extra or {}) do st.weave[k] = v end
  return st
end
local out = {}
local L = WS.Look(S("SWEET", nil), 0, out)
ok(L == out and L.shown == true and L.fillKey == "ranged" and near(L.fill, 0) and L.label == "RANGED" and L.borderKey == "border"
   and L.asGlow == false and L.rsGlow == false and near(L.flash, 0), "in range, no stage: teal, empty, plain border")
L = WS.Look(S("CLOSE", "IN", { glide = 0.4 }), 0, out)
ok(L.fillKey == "dead" and near(L.fill, 0.4) and L.label == "DEAD ZONE" and L.borderKey == "go", "IN through the dead zone: red fill 0.4, green border")
L = WS.Look(S("SWEET", "WAIT"), 0, out)
ok(L.borderKey == "wait", "WAIT: amber border")
L = WS.Look(S("MELEE", "STRIKE", { glide = 1 }), 0, out)
ok(L.fillKey == "melee" and near(L.fill, 1) and L.label == "MELEE" and L.borderKey == "strike" and L.rsGlow == true and L.asGlow == false, "STRIKE: full melee red, Raptor glows")
L = WS.Look(S("CLOSE", "OUT", { glide = 0.6 }), 0, out)
ok(L.borderKey == "out" and near(L.fill, 0.6), "OUT: blue border, draining fill")
L = WS.Look(S("CLOSE", "OUT", { glide = 0.6, legStale = true }), 0, out)
ok(L.borderKey == "stale", "a stale leg: orange border wins")
L = WS.Look(S("SWEET", "RELEASE", { releaseAt = 10 }), 10.1, out)
ok(L.borderKey == "release" and L.asGlow == true and near(L.flash, 0.75), "RELEASE: Auto Shot glows, the flash decays")
-- Overshot (backed past the rest band's outer edge): an amber border, under stale.
L = WS.Look(S("SWEET", nil, { overshot = true }), 0, out)
ok(L.borderKey == "overshot", "overshot: amber border")
L = WS.Look(S("SWEET", nil, { overshot = true, legStale = true }), 0, out)
ok(L.borderKey == "stale", "stale wins over overshot")
L = WS.Look(S("LONG", nil), 0, out)
ok(L.shown == true and L.fillKey == "dead" and L.label == "" and near(L.fill, 0), "too far: no label, empty")
-- The rest band (state.target.ladderRest): green and named; nil / false is the plain zone.
local rs = S("SWEET", nil); rs.target.ladderRest = true
L = WS.Look(rs, 0, out)
ok(L.fillKey == "sweetSpot" and L.label == "SWEET SPOT", "rest band: sweet spot fill and label")
rs.target.ladderRest = false
L = WS.Look(rs, 0, out)
ok(L.fillKey == "ranged" and L.label == "RANGED", "out of the rest band: plain ranged")
-- The unsettled reading lights it while the settled zone still says dead zone (running out).
local raw = S("CLOSE", "OUT"); raw.target.ladderRest = false; raw.target.ladderRestRaw = true
L = WS.Look(raw, 0, out)
ok(L.fillKey == "sweetSpot" and L.label == "SWEET SPOT", "raw rest under a settled dead zone: sweet spot at once")
-- Running in: the raw reading drops first, the settled one holds the look until the zone flips.
raw = S("SWEET", "IN"); raw.target.ladderRest = true; raw.target.ladderRestRaw = false
L = WS.Look(raw, 0, out)
ok(L.fillKey == "sweetSpot" and L.label == "SWEET SPOT", "raw dropped, settled still in: no RANGED flash before the dead zone")
raw.target.ladderRest = false
L = WS.Look(raw, 0, out)
ok(L.label == "RANGED", "both out: plain ranged")
-- Moving toward the target hides it (the plain zone and the glide show); away or standing keeps it.
local mv = S("SWEET", "IN", { glide = 0.3, radial = 1, face = 1 }); mv.target.ladderRest = true; mv.target.ladderRestRaw = true
L = WS.Look(mv, 0, out)
ok(L.fillKey == "ranged" and L.label == "RANGED" and near(L.fill, 0.3), "running in through the band: plain ranged with the glide")
mv.weave.radial, mv.weave.face = 1, -1
L = WS.Look(mv, 0, out)
ok(L.fillKey == "sweetSpot" and L.label == "SWEET SPOT", "running out behind a turn: sweet spot")
mv.weave.radial, mv.weave.face = -1, 1
L = WS.Look(mv, 0, out)
ok(L.label == "SWEET SPOT", "backpedalling out: sweet spot")
mv.weave.radial, mv.weave.face = -1, -1
L = WS.Look(mv, 0, out)
ok(L.label == "RANGED", "backing toward the target while turned away: hidden")
mv.weave.radial, mv.weave.face = 0, 1
L = WS.Look(mv, 0, out)
ok(L.label == "SWEET SPOT", "standing: sweet spot")
-- Range text (weaveStripRangeText): the ladder's brackets until a weave takes over.
local fine = { ["8_20"] = { label = "8-20" }, ["20_25"] = { label = "20-25" }, OOR = { label = "OUT OF RANGE" } }
local function R(zone, key, stage, rest)
  local st = S(zone, stage); st.target.ladderKey = key; st.target.ladderRest = rest
  return st
end
L = WS.Look(R("LONG", "OOR"), 0, out, fine)
ok(L.label == "OUT OF RANGE", "range text: too far reads OUT OF RANGE")
L = WS.Look(R("LONG", "35_40"), 0, out, fine)
ok(L.label == "OUT OF RANGE", "range text: a bracket Auto Shot cannot reach is out of range too")
L = WS.Look(R("SWEET", "20_25"), 0, out, fine)
ok(L.label == "20-25" and L.fillKey == "ranged", "range text: in range with no weave names the bracket")
L = WS.Look(R("SWEET", "8_20", "OUT"), 0, out, fine)
ok(L.label == "RANGED", "range text: a stage hands the bar to the weave words")
L = WS.Look(R("SWEET", "8_20", nil, true), 0, out, fine)
ok(L.label == "SWEET SPOT", "range text: the rest band is the weave's")
L = WS.Look(R("CLOSE", "DEAD"), 0, out, fine)
ok(L.label == "DEAD ZONE", "range text: the dead zone is the weave's")
L = WS.Look(R("MELEE", "MELEE"), 0, out, fine)
ok(L.label == "MELEE", "range text: melee is the weave's")
L = WS.Look(R("SWEET", "unknown"), 0, out, fine)
ok(L.label == "RANGED", "range text: an unknown bracket falls back to RANGED")
L = WS.Look(R("SWEET", "20_25"), 0, out)
ok(L.label == "RANGED", "range text off: unchanged")
L = WS.Look({ target = { exists = false }, weave = {} }, 0, out)
ok(L.shown == false and L.label == "" and L.fillKey == "off", "no target: hidden look")
L = WS.Look({ target = { exists = true, alive = true, friendly = true, rangeState = "SWEET" }, weave = {} }, 0, out)
ok(L.shown == false, "a friendly target: hidden")
for _, k in ipairs({ "dead", "melee", "ranged", "off", "stale", "go", "wait", "strike", "out", "release", "border", "glow" }) do
  ok(type(WS.COLORS[k]) == "table" and #WS.COLORS[k] == 4, "colour " .. k)
end

-- Painter under the stub.
local parent = Stub.CreateFrame("Frame")
local f = WS.Create(parent, { bg = { 0, 0, 0, 1 }, border = { 0, 0, 0, 1 }, fontSize = 9,
  makeText = function(bar) return bar:CreateFontString() end })
ok(f and f.as and f.rs and f.bar and f.bar.fill and f.bar.label and f.as.cd and f.rs.cd, "Create builds two icon slots and the bar")
WS.Layout(f, 220, 18, 1, 1)
ok(f.as._w == 18 and f.rs._w == 18 and f.innerW == 220 - 2 * 18, "Layout: square icons at the row height, the bar between them")
local st = S("CLOSE", "IN", { glide = 0.5 })
st.ranged = { swingStart = 100, swingDuration = 2.6 }
st.cooldowns.Raptor = { startTime = 0, duration = 0, ready = true, spellId = 2973, icon = "icon:2973" }
local fed = {}
f.as.cd.SetCooldown = function(self, s, d) fed[#fed + 1] = { "as", s, d } end
f.rs.cd.SetCooldown = function(self, s, d) fed[#fed + 1] = { "rs", s, d } end
f.rs.cd.SetCooldownFromDurationObject = function(self, obj) fed[#fed + 1] = { "rsobj", obj.id } end
f.rs.cd.Clear = function() fed[#fed + 1] = { "rsclear" } end
local look = WS.Look(st, 0, out)
WS.Paint(f, look, st)
ok(f.bar.fill._w and near(f.bar.fill._w, 0.5 * f.innerW), "fill width = glide x inner width")
ok(f.bar.label._text == "DEAD ZONE", "label painted")
ok(f.as.icon._tex == "icon:75" and f.rs.icon._tex == "icon:2973", "icons: Auto Shot and Raptor")
ok(#fed == 2 and fed[1][1] == "as" and fed[1][2] == 100 and near(fed[1][3], 2.6) and fed[2][1] == "rsclear", "swipes: the ranged swing fed once, Raptor cleared (ready)")
WS.Paint(f, WS.Look(st, 0.1, out), st)
ok(#fed == 2, "unchanged swing: not fed again")
st.ranged.swingStart = 102
st.cooldowns.Raptor.startTime, st.cooldowns.Raptor.duration, st.cooldowns.Raptor.ready = 102, 6, false
WS.Paint(f, WS.Look(st, 0.2, out), st)
ok(#fed == 4 and fed[3][1] == "as" and fed[3][2] == 102 and fed[4][1] == "rsobj" and fed[4][2] == 2973, "new swing and a Raptor cooldown: both fed, Raptor via the duration object")
-- The rest band paints the bar's backdrop green, and puts it back on the way out.
local bgs = {}
f.bar.SetBackdropColor = function(self, r, g, b, a) bgs[#bgs + 1] = { r, g, b, a } end
st.target.ladderRest = true
WS.Paint(f, WS.Look(st, 0.3, out), st)
ok(#bgs == 1 and near(bgs[1][2], WS.COLORS.sweetSpot[2]) and f.bar.label._text == "SWEET SPOT", "rest band: backdrop green, once")
WS.Paint(f, WS.Look(st, 0.4, out), st)
ok(#bgs == 1, "still in the rest band: not painted again")
st.target.ladderRest = false
WS.Paint(f, WS.Look(st, 0.5, out), st)
ok(#bgs == 2 and near(bgs[2][1], 0) and near(bgs[2][2], 0), "left the rest band: the bar's own backdrop back")
local hidden = WS.Look({ target = { exists = false }, weave = {} }, 0, out)
WS.Paint(f, hidden, { ranged = {}, cooldowns = {} })
ok(f.bar.label._text == "" and f.bar.fill._w < 0.02, "no target: label cleared, fill collapsed")

print(("react_weave_strip: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
