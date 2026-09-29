-- Tests/forever_weave_key_test.lua
-- Forever/WeaveKey.lua: stock bodies, pad-button detection, the stuck-toggle decision, the report, and the module's out-of-combat apply.
-- Run from the repo root: luajit Tests/forever_weave_key_test.lua

local pass, fail = 0, 0
local function ok(c, n) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. n) end end

local now = 100
_G.GetTime = function() return now end
local Nock = {
  Flavor = { forever = true, Plain = function(v) return v end },
  db = { profile = {} },
  state = { weave = { keyHeld = false, keyHeldSince = 0 }, target = { rangeState = "SWEET" }, melee = { swingStart = 0, swingRemaining = 0 } },
  Spells = { RAPTOR_STRIKE = 2973 },
}
local module
function Nock:NewModule(name) module = { name = name, events = {}, messages = {} }
  function module:RegisterEvent(ev, h) self.events[ev] = h or ev end
  function module:RegisterMessage(m, h) self.messages[m] = h or m end
  return module end
function Nock:GetModule() return nil end
local printed = {}
function Nock:Print(s) printed[#printed + 1] = s end
_G.LibStub = function() return { GetAddon = function() return Nock end } end
dofile("Forever/WeaveKey.lua")
local K = Nock.WeaveKey
ok(K == module and K.refreshInterval == 0.25, "module WeaveKey, watchdog lane 0.25 s")

-- Bodies: nil = stock, "" = empty, anything else verbatim.
local d, u = K.Bodies({})
ok(d == K.STOCK_DOWN and u == K.STOCK_UP, "unset bodies are the stock ones")
ok(K.STOCK_DOWN == "/click MovePadForward", "stock press = the pad line alone")
ok(K.STOCK_UP == "/click MovePadForward\n/stopcasting\n/cast Raptor Strike\n/startattack\n/cast !Auto Shot\n/run NockCamFlip()\n/run NockCamFace()", "stock release = pad, stopcasting, Raptor, startattack, !Auto Shot, flip, face back")
d, u = K.Bodies({ weaveKeyMacroDown = "", weaveKeyMacroUp = "/cast !Auto Shot\n/startattack" })
ok(d == "" and u == "/cast !Auto Shot\n/startattack", "empty and hand-written bodies come back verbatim")
ok(K.IsStock(K.STOCK_UP .. "\r\n", K.STOCK_UP) and K.IsStock("  " .. K.STOCK_DOWN .. "  \n\n", K.STOCK_DOWN), "IsStock ignores CRLF, trailing blanks and trailing lines")
ok(not K.IsStock("/cast !Auto Shot\n/startattack", K.STOCK_UP), "a body with startattack after !Auto Shot is not stock")
ok(K.Enabled({ weaveKeyEnabled = true }) and not K.Enabled({}) and not K.Enabled(nil), "Enabled reads the mode switch, off by default")

-- Pad buttons named in a body.
local names = K.PadButtons("/click MovePadForward\n/cast x\n/click MovePadBackward\n/click MovePadForward")
ok(#names == 2 and names[1] == "MovePadForward" and names[2] == "MovePadBackward", "pad buttons in order, deduplicated")
ok(#K.PadButtons("") == 0 and #K.PadButtons("/cast Raptor Strike") == 0, "no pad line: nothing to watch")

-- Stuck: a pad toggle checked with no key held for STUCK_AFTER, told once.
local st = {}
ok(not K.Stuck(st, true, true, 100, 100.5), "checked while held: fine")
ok(not K.Stuck(st, true, false, nil, 101), "just released and still checked: not yet")
ok(not K.Stuck(st, true, false, nil, 101.9), "under a second: not yet")
ok(K.Stuck(st, true, false, nil, 102.1), "a second later: stuck")
ok(not K.Stuck(st, true, false, nil, 103), "told once")
ok(not K.Stuck(st, false, false, nil, 104), "unchecked: clear")
ok(not K.Stuck(st, true, false, nil, 106), "a new incident arms again")
ok(K.Stuck(st, true, false, nil, 107.1), "and tells again a second later")
local st2 = {}
ok(not K.Stuck(st2, true, true, 100, 105), "a hold 5 s old still counts as held")
K.Stuck(st2, true, true, 100, 111)
ok(K.Stuck(st2, true, true, 100, 112.1), "a hold older than HOLD_STALE counts as released: stuck")
ok(not K.Stuck({}, false, false, nil, 200), "nothing checked, nothing held: silent (no pad line case)")

-- Report text.
local text = K.Report({
  enabled = true, key = "SHIFT-F", down = K.STOCK_DOWN, up = K.STOCK_UP, built = true, bound = true, padLoaded = true,
  flipOn = true, pad = { { name = "MovePadForward", checked = false } },
  edges = { { t = 10, down = true, zone = "SWEET", mrem = 0.2, combat = true }, { t = 11.5, down = false, zone = "MELEE", mrem = 0, combat = true } },
  casts = { { t = 11.6, ev = "SUCCEEDED", name = "Raptor Strike" } },
})
ok(text:find("key: SHIFT-F", 1, true) and text:find("mode: on", 1, true), "report header")
ok(text:find("release:\n/click MovePadForward | /stopcasting", 1, true), "bodies shown as lines")
ok(text:find("11.500  release  zone MELEE  meleeIn 0.00  combat true", 1, true), "edge rows")
ok(text:find("11.600  cast SUCCEEDED  Raptor Strike", 1, true), "cast rows merged by time")
ok(text:find("MovePadForward checked false", 1, true), "pad state")

-- Runtime: apply out of combat builds the button, writes the bodies and binds;
-- in combat it defers and touches nothing; the regen event applies once.
local attrs, binds, cleared, frames = {}, {}, 0, {}
local combat = false
_G.InCombatLockdown = function() return combat end
_G.UIParent = {}
_G.CreateFrame = function(kind, name)
  local f = { name = name, scripts = {}, hooks = {} }
  function f:SetAttribute(k, v) attrs[k] = v end
  function f:GetAttribute(k) return attrs[k] end
  function f:RegisterForClicks(...) f.clicks = { ... } end
  function f:HookScript(ev, fn) f.hooks[ev] = fn end
  frames[name] = f
  return f
end
_G.SecureHandlerWrapScript = function(b, ev, h, body) b.wrapped = ev end
_G.ClearOverrideBindings = function() cleared = cleared + 1 end
_G.SetOverrideBindingClick = function(owner, prio, key, button) binds[#binds + 1] = key .. ">" .. button end
_G.MovePad_LoadUI = function() _G.MovePadForward = { GetChecked = function() return false end } end
local p = Nock.db.profile
p.weaveKeyEnabled, p.weaveKey = true, "SHIFT-F"
K:OnEnable()
ok(K.messages.NOCK_WEAVEKEY_CHANGED == "Apply" and K.events.PLAYER_REGEN_ENABLED, "listens for changes and the regen edge")
ok(frames.NockWeaveKey and frames.NockWeaveKey.wrapped == "OnClick" and frames.NockWeaveKey.clicks[2] == "AnyUp", "button built, wrapped, both edges")
ok(attrs.type == "macro" and attrs.macrotextDown == K.STOCK_DOWN and attrs.macrotextUp == K.STOCK_UP, "stock bodies on the button")
ok(binds[#binds] == "SHIFT-F>NockWeaveKey", "bound to the key")
-- In combat: nothing moves.
combat = true
p.weaveKey = "SHIFT-G"
local n = #binds
K:Apply()
ok(#binds == n and K._pending == true, "combat: deferred")
combat = false
K:PLAYER_REGEN_ENABLED()
ok(binds[#binds] == "SHIFT-G>NockWeaveKey" and K._pending == nil, "regen: applied once")
-- Mode off: the binding goes, the button stays.
p.weaveKeyEnabled = false
local c = cleared
K:Apply()
ok(cleared == c + 1 and #binds == n + 1, "off: cleared, not rebound")
p.weaveKeyEnabled = true; K:Apply()

-- Edges: recorded, published, no attribute touched even in combat.
combat = true
local before = attrs.macrotextUp
K:OnEdge(true); now = 100.4
ok(Nock.state.weave.keyHeld == true and Nock.state.weave.keyHeldSince == 100, "press publishes keyHeld")
K:OnEdge(false)
ok(Nock.state.weave.keyHeld == false and #K._edges == 2 and K._edges[2].t == 100.4 and K._edges[2].zone == "SWEET", "release recorded with the zone")
ok(attrs.macrotextUp == before, "an edge never writes an attribute")
combat = false

-- Watchdog through Refresh: the pad checked with no key held for a second.
local checked = false
_G.MovePadForward.GetChecked = function() return checked end
now = 110; K:Refresh(Nock.state)
checked = true; now = 110.5; K:Refresh(Nock.state)
ok(#printed == 0, "half a second: quiet")
now = 111.6; K:Refresh(Nock.state)
ok(#printed == 1 and printed[1]:find("stuck", 1, true) and printed[1]:find("/click MovePadForward", 1, true), "a second later: the one-line fix names the command that re-syncs")
now = 112; K:Refresh(Nock.state)
ok(#printed == 1, "told once")
p.weaveKeyEnabled = false; checked = true; now = 120; K:Refresh(Nock.state)
ok(#printed == 1, "mode off: the watchdog is off")

-- Review fixes (2026-09-29): a profile switch reaches the key; the bodies
-- follow the mode, not the key (the game's own Key Bindings entry); a lost
-- release edge (death, loading screen) drops the hold at once.
ok(K.messages.NOCK_WEAVEBIND_CHANGED == "Apply", "the profile-switch message (sent by the core) re-applies the key")
ok(K.events.PLAYER_DEAD == "OnHoldLost" and K.events.PLAYER_ENTERING_WORLD == "OnHoldLost", "death and loading screens drop the hold")
p.weaveKeyEnabled, p.weaveKey = true, nil
local nb = #binds
K:Apply()
ok(attrs.macrotextDown == K.STOCK_DOWN and attrs.macrotextUp == K.STOCK_UP and #binds == nb, "mode on without Nock's key: bodies on the button (for a game binding), no override")
p.weaveKeyEnabled = false
K:Apply()
ok(attrs.macrotextDown == "" and attrs.macrotextUp == "", "mode off: both bodies cleared, a game binding runs nothing")
p.weaveKeyEnabled, p.weaveKey = true, "SHIFT-F"
K:Apply()
K:OnEdge(true)
ok(Nock.state.weave.keyHeld == true, "held")
K:OnHoldLost("PLAYER_DEAD")
ok(Nock.state.weave.keyHeld == false, "death: the hold is dropped so the watchdog can speak within a second")

print(("forever_weave_key: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
