-- Tests/forever_keybinds_test.lua
-- Forever/KeyBinds.lua: the pure helpers (list, key owner, summary, list
-- edits, clamp) and Apply on a stubbed secure API (bodies, overrides, combat).
-- Run from the repo root: luajit Tests/forever_keybinds_test.lua
local pass, fail = 0, 0
local function ok(c, n) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. n) end end

local combat = false
local secureCalls = 0
local overrides = {}          -- button name -> { key = true }
local made = {}               -- name -> button
_G.InCombatLockdown = function() return combat end
_G.UIParent = {}
_G.CreateFrame = function(_, name)
  local b = { name = name, attrs = {} }
  function b:SetAttribute(k, v) secureCalls = secureCalls + 1; self.attrs[k] = v end
  function b:RegisterForClicks() end
  function b:GetName() return self.name end
  made[name] = b
  return b
end
_G.SecureHandlerWrapScript = function() end
_G.SetOverrideBindingClick = function(b, _, key, name) secureCalls = secureCalls + 1; overrides[name] = overrides[name] or {}; overrides[name][key] = true end
_G.ClearOverrideBindings = function(b) secureCalls = secureCalls + 1; overrides[b.name] = nil end

local Nock = { Flavor = { forever = true, Plain = function(v) return v end }, db = { profile = {} } }
function Nock:Print() end
local module
function Nock:NewModule(name)
  module = { name = name, events = {}, msgs = {} }
  function module:RegisterEvent(ev, h) self.events[ev] = h or ev end
  function module:RegisterMessage(m, h) self.msgs[m] = h or m end
  return module
end
_G.LibStub = function() return { GetAddon = function() return Nock end } end
dofile("Forever/KeyBinds.lua")
local KB = Nock.KeyBinds
ok(KB and module and module.name == "KeyBinds", "module KeyBinds registered as Nock.KeyBinds")

-- List
do
  local p = {}
  local l = KB.List(p)
  ok(type(l) == "table" and #l == 0 and p.keyBinds == l, "List creates and stores an empty list")
  ok(#KB.List({ keyBinds = { 1, { name = "a" } } }) == 1, "List drops non-table entries")
end

-- KeyOwner
do
  local l = { { name = "A", key = "SHIFT-E" }, { name = "B", key = "F" } }
  ok(KB.KeyOwner(l, "SHIFT-E", 2, "G") == "bind:A", "another bind holds the key")
  ok(KB.KeyOwner(l, "SHIFT-E", 1, "G") == nil, "a bind's own key is free for it")
  ok(KB.KeyOwner(l, "G", 1, "G") == "weave key", "the weave key holds it")
end

-- Summary
ok(KB.Summary({ down = "/cast Raptor Strike", up = "/cast Mongoose Bite" }) == "↓ Raptor Strike  ↑ Mongoose Bite", "summary names both casts")
ok(KB.Summary({}) == "↓ empty  ↑ empty", "summary of an empty bind")
ok(KB.Summary({ down = "/startattack\n/cast [nodead] Wing Clip", up = "/say hi" }) == "↓ Wing Clip  ↑ /say hi", "summary: first cast, conditions stripped; else the first line")

-- New / Duplicate / Remove / Clamp
do
  local l = {}
  ok(KB.New(l) == 1 and #l == 1, "New appends and returns its index")
  l[1].key, l[1].name, l[1].down = "E", "x", "/cast A"
  ok(KB.Duplicate(l, 1) == 2 and #l == 2 and l[2].key == nil and l[2].down == "/cast A", "Duplicate copies after, without the key")
  KB.New(l)
  ok(KB.Remove(l, 3) == 2 and #l == 2, "removing the last selects the one before")
  ok(KB.Remove(l, 1) == 1 and #l == 1, "removing the first selects the new first")
  ok(KB.Remove(l, 1) == 0 and #l == 0, "removing the only one leaves nothing selected")
  ok(KB.Clamp({ {}, {}, {} }, 9) == 3 and KB.Clamp({}, 1) == 0 and KB.Clamp({ {} }, 0) == 1, "Clamp")
end

-- FirstSpell: the first spell a body casts, for the list icons
ok(KB.FirstSpell("/cast Raptor Strike") == "Raptor Strike", "FirstSpell: a plain cast")
ok(KB.FirstSpell("/startattack\n/cast [nodead] Wing Clip") == "Wing Clip", "FirstSpell: skips non-cast lines, drops conditions")
ok(KB.FirstSpell("/cast !Auto Shot") == "Auto Shot", "FirstSpell: drops the leading !")
ok(KB.FirstSpell("/cast [mod:shift] Mongoose Bite; Raptor Strike") == "Mongoose Bite", "FirstSpell: the first clause of a ; list")
ok(KB.FirstSpell("/use Snowball") == "Snowball", "FirstSpell: /use counts")
ok(KB.FirstSpell("/say hi") == nil and KB.FirstSpell("") == nil and KB.FirstSpell(nil) == nil, "FirstSpell: nothing cast -> nil")
-- Icon: spell first, then item, else nil (API stubbed)
Nock.API = { SpellInfo = function(n) if n == "Raptor Strike" then return n, 132223 end end,
             ItemIconByName = function(n) if n == "Snowball" then return 132387 end end }
ok(KB.Icon("Raptor Strike") == 132223 and KB.Icon("Snowball") == 132387 and KB.Icon("Nope") == nil and KB.Icon(nil) == nil, "Icon: spell, item, none")

-- New binds start empty; no starter fill
do
  local l = {}
  KB.New(l)
  ok(l[1].down == "" and l[1].up == "" and l[1].key == nil, "New: both macros empty, no key")
  ok(KB.Fill == nil and KB.STARTER == nil, "no starter fill")
  ok(KB.MAX_BODY == 255, "255 characters per body")
end

-- Apply
do
  local p = Nock.db.profile
  p.keyBinds = { { name = "A", key = "SHIFT-E", down = "/cast X", up = "/cast Y" }, { name = "B", down = "/cast Z", up = "" } }
  module:OnEnable()
  local b1, b2 = made.NockKeyBind1, made.NockKeyBind2
  ok(b1 and b1.attrs.macrotextDown == "/cast X" and b1.attrs.macrotextUp == "/cast Y", "bind 1 bodies set")
  ok(overrides.NockKeyBind1 and overrides.NockKeyBind1["SHIFT-E"], "bind 1 key bound")
  ok(b2 and b2.attrs.macrotextDown == "/cast Z" and overrides.NockKeyBind2 == nil, "keyless bind: bodies, no override")
  ok(module:Pending() == false, "nothing pending")

  combat = true
  local before = secureCalls
  p.keyBinds[1].down = "/cast W"
  module:Apply()
  ok(secureCalls == before and module:Pending() == true, "in combat: no secure call, pending")
  combat = false
  module:PLAYER_REGEN_ENABLED()
  ok(b1.attrs.macrotextDown == "/cast W" and module:Pending() == false, "applied at regen")

  table.remove(p.keyBinds, 1)
  module:Apply()
  ok(b1.attrs.macrotextDown == "/cast Z" and overrides.NockKeyBind1 == nil, "list shifts onto button 1")
  ok(b2.attrs.macrotextDown == "" and b2.attrs.macrotextUp == "" and overrides.NockKeyBind2 == nil, "freed button emptied, unbound")
  KB.selected = 5
  module:Apply()
  ok(KB.selected == 1, "Apply clamps the selection")
end

print(("forever_keybinds: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
