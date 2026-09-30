-- Tests/forever_quickstart_test.lua
-- Forever/Quickstart.lua: each weave card's readiness from the profile and the client facts, the tally, the open rule, the macro scan. Pure.
-- Run from the repo root: luajit Tests/forever_quickstart_test.lua

local pass, fail = 0, 0
local function ok(c, n) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. n) end end

local Nock = { Flavor = { forever = true } }
_G.LibStub = function() return { GetAddon = function() return Nock end } end
dofile("Forever/Quickstart.lua")
local Q = Nock.Quickstart
ok(type(Q) == "table", "Nock.Quickstart registered")

-- The card list: five cards in setup order, every row a dotted option path.
local keys = {}
for i, c in ipairs(Q.WEAVE) do
  keys[i] = c.key
  ok(type(c.name) == "string" and type(c.icon) == "string", "card has a name and a glyph: " .. c.key)
  for _, r in ipairs(c.rows) do ok(type(r[1]) == "string" and r[1]:find("%."), "row is an option path on " .. c.key) end
end
ok(table.concat(keys, ",") == "hud,camera,key,macros,sounds", "cards in setup order, got " .. table.concat(keys, ","))
ok(Q.Card("hud").master == "hud.react.tabSize.weaveHelperEnabled" and Q.Card("camera").master == "utilities.cameraFlip.cameraFlipEnabled"
   and Q.Card("key").master == "utilities.weaveKey.weaveKeyEnabled", "three cards carry a master switch")
ok(Q.Card("macros").master == nil and Q.Card("sounds").master == nil and Q.Card("nope") == nil, "macros and sounds have none; unknown key is nil")
ok(Q.Card("macros").hidden({ weaveKeyEnabled = true }) == true and Q.Card("macros").hidden({}) == false, "macros card hides in key mode")

local READY_ENV = { cameraSetupDone = true, cameraStyle = "0", movePad = true, macroFlip = true, macroFace = true }
local function prof(over)
  local p = { weaveHelperEnabled = true, reactShowMeleeBar = true, reactMeleeStageCue = true, reactShowWeaveStrip = true,
    hudEnabled = true, cameraFlipEnabled = true, cameraFlipGate = "raid", weaveKeyEnabled = false,
    soundCuesEnabled = true, weaveStrikeEnabled = false, weaveReleaseEnabled = false, cueDeadZoneEnabled = false, cueMeleeEnabled = false }
  for k, v in pairs(over or {}) do p[k] = v end
  return p
end
local function st(over, env) return Q.WeaveStatus(prof(over), env or READY_ENV) end

-- HUD card.
local s = st()
ok(s.hud.state == "ready" and s.hud.pill == "READY" and s.hud.line:find("melee bar") and s.hud.line:find("strip"), "hud: ready, the line names what shows")
ok(st({ weaveHelperEnabled = false }).hud.state == "off" and st({ weaveHelperEnabled = false }).hud.pill == "OFF", "hud: helper off reads OFF")
s = st({ hudEnabled = false })
ok(s.hud.state == "attention" and s.hud.pill == "HUD HIDDEN", "hud: a hidden HUD needs you")
s = st({ reactShowMeleeBar = false })
ok(s.hud.state == "attention" and s.hud.pill == "MELEE BAR OFF", "hud: the words need the melee bar")
s = st({ hudEnabled = false, reactShowMeleeBar = false })
ok(s.hud.pill == "HUD HIDDEN" and #s.hud.problems == 2 and s.hud.line:find("melee swing bar"), "hud: first problem on the pill, every problem in the line")
-- Review focus 2: unset keys read as the option's own get reads them (helper ON).
ok(Q.WeaveStatus({}, {}).hud.state ~= "off", "hud: an unset helper key reads on, like its switch")

-- Camera card.
s = st()
ok(s.camera.state == "ready" and s.camera.line == "On, raid only", "camera: ready, the gate in the line")
ok(st({ cameraFlipGate = "solo" }).camera.line == "On, everywhere" and st({ cameraFlipGate = "party" }).camera.line == "On, party and raid", "camera: gate labels")
ok(st({ cameraFlipEnabled = false }).camera.state == "off", "camera: flip off reads OFF")
s = st({ cameraFlipEnabled = false, weaveKeyEnabled = true })
ok(s.camera.state == "attention" and s.camera.pill == "TURN IT ON", "camera: the weave key wants the flip")
s = st(nil, { cameraSetupDone = false, cameraStyle = "0" })
ok(s.camera.state == "attention" and s.camera.pill == "SET UP CAMERA", "camera: never set up")
s = st(nil, { cameraSetupDone = true, cameraStyle = "2" })
ok(s.camera.state == "attention" and s.camera.pill == "FIX CAMERA STYLE", "camera: following style wrong")
s = st(nil, { cameraSetupDone = false, cameraStyle = "2" })
ok(s.camera.pill == "SET UP CAMERA" and #s.camera.problems == 2, "camera: setup first, both listed")
-- Review focus 3: facts that cannot be read are never a problem.
ok(st(nil, {}).camera.state == "ready", "camera: unknown setup and style are not problems")

-- Weave key card.
ok(st().key.state == "off" and st().key.line == "One-key weaving is off.", "key: mode off reads OFF, true for a turret too")
s = st({ weaveKeyEnabled = true })
ok(s.key.state == "attention" and s.key.pill == "BIND A KEY", "key: mode on without a key")
s = st({ weaveKeyEnabled = true, weaveKey = "" })
ok(s.key.pill == "BIND A KEY", "key: an empty binding is no key")
s = st({ weaveKeyEnabled = true, weaveKey = "SHIFT-F" }, { cameraSetupDone = true, cameraStyle = "0", movePad = false })
ok(s.key.state == "attention" and s.key.pill == "NO MOVEMENT PAD", "key: the pad cannot load")
s = st({ weaveKeyEnabled = true, weaveKey = "SHIFT-F" })
ok(s.key.state == "ready" and s.key.line == "Key: SHIFT-F", "key: ready names the key")
ok(st({ weaveKeyEnabled = true, weaveKey = "SHIFT-F" }, {}).key.state == "ready", "key: an unknown pad is not a problem")
-- Review: the key can also be bound in the game's Key Bindings window.
s = st({ weaveKeyEnabled = true }, { movePad = true, bindingKey = "BUTTON4" })
ok(s.key.state == "ready" and s.key.line == "Key: BUTTON4", "key: a key bound in the game's Key Bindings counts")
s = st({ weaveKeyEnabled = true, weaveKey = "SHIFT-F" }, { movePad = true, bindingKey = "BUTTON4" })
ok(s.key.line == "Key: SHIFT-F", "key: Nock's own key wins, as it does when both are set")

-- Macros card.
ok(st({ weaveKeyEnabled = true }).macros == nil, "macros: no entry in key mode")
ok(st({ cameraFlipEnabled = false }).macros.state == "off" and st({ cameraFlipEnabled = false }).macros.pill == "NOT NEEDED", "macros: nothing needed without the flip")
ok(st().macros.state == "ready", "macros: both camera lines found")
s = st(nil, { cameraSetupDone = true, cameraStyle = "0", macroFlip = true, macroFace = false })
ok(s.macros.state == "attention" and s.macros.pill == "ADD CAMERA LINES" and s.macros.line:find("NockCamFace"), "macros: the missing line is named")
s = st(nil, { cameraSetupDone = true, cameraStyle = "0", macroFlip = false, macroFace = false })
ok(s.macros.line:find("NockCamFlip") and s.macros.line:find("NockCamFace"), "macros: both missing, both named")
s = st(nil, { cameraSetupDone = true, cameraStyle = "0" })
ok(s.macros.state == "none" and s.macros.pill == "", "macros: unreadable macros show no status")

-- Sounds card.
ok(st().sounds.state == "off", "sounds: nothing on reads OFF")
s = st({ weaveStrikeEnabled = true, weaveStrikeSound = "Nock Strike", cueDeadZoneEnabled = true })
ok(s.sounds.state == "ready" and s.sounds.line == "Strike, dead zone", "sounds: ready lists the cues, got " .. tostring(s.sounds.line))
s = st({ weaveReleaseEnabled = true, weaveReleaseSound = "Clip", soundCuesEnabled = false })
ok(s.sounds.state == "attention" and s.sounds.pill == "CUES MUTED", "sounds: a cue under a muted master")
-- Review focus 1: a cue switched on with the default clip plays nothing.
s = st({ weaveStrikeEnabled = true, weaveStrikeSound = "None" })
ok(s.sounds.state == "attention" and s.sounds.pill == "PICK A CLIP" and s.sounds.line:find("Strike"), "sounds: a cue without a clip is not ready")
s = st({ weaveReleaseEnabled = true })
ok(s.sounds.pill == "PICK A CLIP" and s.sounds.line:find("Release"), "sounds: an unset clip counts as none")
ok(st({ soundCuesEnabled = false }).sounds.state == "off", "sounds: a muted master with nothing on is just off")
-- Review: the range voice lines ship on for everyone; alone they are not a
-- weave cue, so a turret's card reads OFF.
s = st({ cueDeadZoneEnabled = true, cueMeleeEnabled = true })
ok(s.sounds.state == "off" and s.sounds.pill == "OFF" and s.sounds.line:find("dead zone, melee"), "sounds: voice lines alone read OFF and are named, got " .. tostring(s.sounds.line))
s = st({ cueDeadZoneEnabled = true, soundCuesEnabled = false })
ok(s.sounds.state == "off", "sounds: a muted voice line is not a weave problem")

-- Tally and its text.
local t = Q.Tally(st({ weaveKeyEnabled = true }, { cameraSetupDone = false, cameraStyle = "0", movePad = true }))
ok(t.attention == 2 and t.ready == 1 and t.off == 1, ("tally: 2 need you, 1 ready, 1 off (got %d/%d/%d)"):format(t.attention, t.ready, t.off))
ok(Q.TallyText(t) == "2 need you · 1 ready · 1 off", "tally text, got " .. Q.TallyText(t))
ok(Q.TallyText({ attention = 1, ready = 0, off = 3 }) == "1 needs you · 3 off", "tally text: singular, zero parts dropped")
ok(Q.TallyText({ attention = 0, ready = 4, off = 0 }) == "4 ready", "tally text: all ready")
ok(Q.Tally(st(nil, { cameraSetupDone = true, cameraStyle = "0" })).ready == 2, "tally: a card without status is not counted")

-- A card is open when it needs you, unless the user chose otherwise.
ok(Q.CardOpen("attention", nil) == true and Q.CardOpen("ready", nil) == false and Q.CardOpen("off", nil) == false, "open by default only when it needs you")
ok(Q.CardOpen("attention", false) == false and Q.CardOpen("ready", true) == true, "the user's click wins")
ok(Q.CardOpen("none", nil) == true, "a card without status is open: its button is all it has")
-- The head's open/close cue: a chevron and a word, both ways.
ok(Q.OpenCue(false).glyph == "chevrondown" and Q.OpenCue(false).text == "SHOW", "closed card: chevron down, SHOW")
ok(Q.OpenCue(true).glyph == "chevronup" and Q.OpenCue(true).text == "HIDE", "open card: chevron up, HIDE")

-- Macro scan. Review focus 3: bodies that are not strings are skipped.
ok(select("#", Q.MacroLines(nil)) == 2 and Q.MacroLines(nil) == nil, "no macro list: cannot tell")
local flip, face = Q.MacroLines({ "/cast Raptor Strike\n/run NockCamFlip()", 42, false, "/cast !Auto Shot\n/run NockCamFace()" })
ok(flip == true and face == true, "both lines found across macros, junk entries skipped")
flip, face = Q.MacroLines({ "/run NockCamFlip(true)" })
ok(flip == true and face == false, "the flip alone")
flip, face = Q.MacroLines({})
ok(flip == false and face == false, "no macros: neither line")
flip, face = Q.MacroLines({ "/run NockCamFlip()" }, 2)
ok(flip == true and face == nil, "unreadable bodies: a found line stands, a missing one is unknown")

-- Env: nothing to read is nothing known, and never an error.
local env = Q.Env({})
ok(type(env) == "table" and env.cameraSetupDone == nil and env.cameraStyle == nil and env.movePad == nil and env.macroFlip == nil, "env: a bare client yields no facts")
Nock.db = { char = { cameraSetupDone = true }, profile = {} }
_G.GetCVar = function(n) return n == "cameraSmoothStyle" and 0 or nil end
_G.GetNumMacros = function() return 1, 1 end
_G.MAX_ACCOUNT_MACROS = 120
_G.GetMacroBody = function(i) if i == 1 then return "/run NockCamFlip()" elseif i == 121 then return "/run NockCamFace()" end error("bad index " .. tostring(i)) end
local loads = 0
Nock.WeaveKey = { LoadPad = function() loads = loads + 1; return true end }
env = Q.Env({ weaveKeyEnabled = false })
ok(env.cameraSetupDone == true and env.cameraStyle == "0" and env.macroFlip == true and env.macroFace == true, "env: stamp, style as a string, account and character macros")
ok(env.movePad == nil and loads == 0, "env: the pad is not loaded while key mode is off")
env = Q.Env({ weaveKeyEnabled = true })
ok(env.movePad == true and loads == 1, "env: key mode asks the pad")
_G.GetMacroBody = function() error("secret") end
env = Q.Env({})
ok(env.macroFlip == nil and env.macroFace == nil, "env: macros that cannot be read are unknown, not missing")
_G.GetMacroBody = function(i) if i == 1 then return "/run NockCamFlip()" end return nil end
env = Q.Env({})
ok(env.macroFlip == true and env.macroFace == nil, "env: one body read, one not: the found line stands, the other is unknown")
_G.GetBindingKey = function(a) return a == "CLICK NockWeaveKey:LeftButton" and "BUTTON4" or nil end
ok(Q.Env({ weaveKeyEnabled = true }).bindingKey == "BUTTON4" and Q.Env({}).bindingKey == nil, "env: the game binding, asked in key mode only")

-- StatusFor: the weaving page only, memoised per frame until invalidated.
ok(Q.StatusFor("alerts.warnings") == nil, "no status for other pages")
_G.GetMacroBody = function(i) return i == 1 and "/run NockCamFlip() /run NockCamFace()" or nil end
_G.GetTime = function() return 10 end
Nock.db.profile = prof()
local a = Q.StatusFor("quickstarts.weaving")
ok(a and a.hud.state == "ready", "status for the weaving page")
Nock.db.profile.weaveHelperEnabled = false
ok(Q.StatusFor("quickstarts.weaving") == a, "same frame: the memo")
Q.Invalidate()
ok(Q.StatusFor("quickstarts.weaving").hud.state == "off", "invalidated: read again")

print(("forever_quickstart: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
