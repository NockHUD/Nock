-- Regression guard for Config/Options.lua: every `values` table handed to an
-- LSM media dropdown must satisfy key == value for EVERY entry.
--
-- Why this rule exists. All LSM preview widgets (the foreign LSM30_* from
-- AceGUI-3.0-SharedMediaWidgets, and our own Nock_LSM_* in
-- UI/AceGUI_LSMDropdown.lua) resolve a row's media as
--     list[key] ~= key and list[key] or LSM:Fetch(mediaType, key)
-- so an entry whose VALUE differs from its KEY is read as "the value IS the
-- media path". A sentinel written as t[""] = "Reference (built-in)" therefore
-- reached FontString:SetFont() as a literal path. The error that raised was
-- swallowed by nothing: AceConfigDialog's option loop has no pcall, so it
-- aborted and every control BELOW that one silently never rendered — the
-- "React tab goes blank after Bar texture" report. Textures fail silently
-- where fonts throw, which is exactly why the bar texture row still appeared.
--
-- Run from the repo root: luajit Tests/options_lsm_values_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end

local registered
local libs = {}
libs["AceAddon-3.0"] = { GetAddon = function() return _G.NockStub end }
libs["AceConfig-3.0"] = { RegisterOptionsTable = function(_, _, opts) registered = opts end }
libs["AceDBOptions-3.0"] = { GetOptionsTable = function() return { type = "group", name = "Profiles", args = {} } end }
libs["AceConfigDialog-3.0"] = { AddToBlizOptions = function() return {} end }
-- lsmWidget() resolves through the REAL Nock.UI.PreferredMediaWidget, so this
-- has to be a working-enough AceGUI for UI/AceGUI_LSMDropdown.lua to register
-- its widgets into. Stubbing the answer instead would let the preference order
-- drift from what ships without any test noticing.
libs["AceGUI-3.0"] = {
  WidgetRegistry = {},
  RegisterWidgetType = function(self, name, ctor) self.WidgetRegistry[name] = ctor end,
}
-- Non-nil so the widget file doesn't bail; List() drives lsmValues(), and an
-- empty media list leaves each values table holding only its sentinel rows --
-- precisely what this test is about.
libs["LibSharedMedia-3.0"] = {
  List = function() return {} end,
  Fetch = function() return nil end,
  Register = function() return true end,
}
_G.LibStub = setmetatable({}, {
  __call = function(_, name, silent)
    local lib = libs[name]
    if not lib and not silent then error("harness: missing lib " .. name) end
    return lib
  end,
})

local Nock = {
  db = { profile = {} },
  Constants = setmetatable({}, {
    __index = function(t, k) local v = {}; rawset(t, k, v); return v end,
  }),
}
function Nock:GetModule() return nil end
function Nock:SendMessage() end
_G.NockStub = Nock

-- .toc order: Config/Options.lua (18) loads BEFORE UI/AceGUI_LSMDropdown.lua
-- (22). Mirrored here on purpose -- it proves lsmWidget()'s lazy resolution
-- still finds the widgets even though they register after the options file.
dofile("Config/Options.lua")
dofile("UI/AceGUI_LSMDropdown.lua")
Nock:RegisterOptions()

-- Widget names that render an LSM media preview and therefore enforce the
-- key == value contract. "plain" is exempt: it has no preview and never
-- resolves a path (it only normalises the pooled item font).
local MEDIA_WIDGETS = {
  Nock_LSM_Statusbar = true, Nock_LSM_Font = true,
  LSM30_Statusbar = true, LSM30_Font = true,
}

local checked, offenders = 0, {}
local function walk(args, path)
  for key, entry in pairs(args) do
    if type(entry) == "table" then
      local here = path .. "." .. tostring(key)
      if entry.type == "select" and MEDIA_WIDGETS[entry.dialogControl] then
        checked = checked + 1
        local values = entry.values
        if type(values) == "function" then values = values() end
        if type(values) == "table" then
          for k, v in pairs(values) do
            if k ~= v then
              offenders[#offenders + 1] = ("%s [%q]=%q"):format(here, tostring(k), tostring(v))
            end
          end
        end
      end
      if entry.args then walk(entry.args, here) end
    end
  end
end
walk(registered.args, "root")

ok(checked > 0, "found LSM media selects to check (found " .. checked .. ")")
ok(#offenders == 0,
   "every LSM media select has key == value (offenders: " .. table.concat(offenders, ", ") .. ")")

-- The four known sentinel selects must still OFFER their sentinel row, or the
-- fix above would "pass" by silently dropping the Reference/Inherit option.
local found = {}
local function walk2(args)
  for key, entry in pairs(args) do
    if type(entry) == "table" then
      if entry.type == "select" and MEDIA_WIDGETS[entry.dialogControl] then
        local values = entry.values
        if type(values) == "function" then values = values() end
        if type(values) == "table" then
          for k in pairs(values) do found[key] = found[key] or {}; found[key][k] = true end
        end
      end
      if entry.args then walk2(entry.args) end
    end
  end
end
walk2(registered.args)

local EXPECTED_SENTINEL = {
  autoShotBarTexture = "Inherit (global)",
  meleeBarTexture    = "Inherit (global)",
  reactBarTexture    = "Reference (built-in)",
  reactFont          = "Reference (built-in)",
}
for optKey, label in pairs(EXPECTED_SENTINEL) do
  ok(found[optKey] and found[optKey][label],
     ("%s still offers its %q row"):format(optKey, label))
end

-- And the "" <-> label mapping must round-trip, so nothing that reads the raw
-- profile key (UI/Widgets.lua's GetReactFont et al) sees a changed contract.
local function findOpt(args, want)
  for key, entry in pairs(args) do
    if type(entry) == "table" then
      if key == want and entry.type == "select" then return entry end
      if entry.args then local r = findOpt(entry.args, want); if r then return r end end
    end
  end
end
for optKey, label in pairs(EXPECTED_SENTINEL) do
  local opt = findOpt(registered.args, optKey)
  ok(opt ~= nil, optKey .. " option found")
  if opt then
    Nock.db.profile[optKey] = ""
    ok(opt.get({}) == label, optKey .. ': stored "" reads back as the sentinel label')
    opt.set({}, label)
    ok(Nock.db.profile[optKey] == "", optKey .. ": choosing the sentinel stores \"\"")
    opt.set({}, "SomeFont")
    ok(Nock.db.profile[optKey] == "SomeFont", optKey .. ": a real media name stores verbatim")
    ok(opt.get({}) == "SomeFont", optKey .. ": a real media name reads back verbatim")
  end
end

-- Layer 1: our own widgets must win even when a foreign SharedMediaWidgets is
-- also loaded. LSM30_* is not embedded by Nock, exists at versions 11-13 in the
-- wild, and the old ones throw on this client -- so "ours first" is the whole
-- reason the panel can't be truncated by someone else's library.
libs["AceGUI-3.0"].WidgetRegistry.LSM30_Statusbar = function() end
libs["AceGUI-3.0"].WidgetRegistry.LSM30_Font = function() end
ok(Nock.UI.PreferredMediaWidget("statusbar") == "Nock_LSM_Statusbar",
   "statusbar prefers Nock_LSM_Statusbar over LSM30_Statusbar")
ok(Nock.UI.PreferredMediaWidget("font") == "Nock_LSM_Font",
   "font prefers Nock_LSM_Font over LSM30_Font")
ok(Nock.UI.PreferredMediaWidget("plain") == "Nock_LSM_Plain", "plain resolves")
ok(Nock.UI.PreferredMediaWidget("nosuchtype") == nil, "unknown media type resolves to nil")

-- ...and LSM30_* is still reachable as the last resort, for the case where
-- UI/AceGUI_LSMDropdown.lua itself failed to load.
libs["AceGUI-3.0"].WidgetRegistry.Nock_LSM_Font = nil
ok(Nock.UI.PreferredMediaWidget("font") == "LSM30_Font",
   "font falls back to LSM30_Font when ours is absent")

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
