-- Tests/lib/options_harness.lua
-- Registers the real Config/Options.lua table against stub Ace libs; returns Nock, the walker and the registered table.
return function(opts)
  opts = opts or {}
  local registered, notified, callbacks = nil, 0, {}
  local libs = {}
  libs["AceAddon-3.0"] = { GetAddon = function() return _G.NockStub end }
  libs["AceConfig-3.0"] = { RegisterOptionsTable = function(_, _, opts) registered = opts end }
  libs["AceDBOptions-3.0"] = { GetOptionsTable = function() return { type = "group", name = "Profiles",
    handler = { GetCurrentProfile = function() return "Default" end, ListProfiles = function() return { Default = "Default" } end,
                HasNoProfiles = function() return true end, SetProfile = function(self, info, v) self.set = v end },
    args = {
      current = { type = "description", order = 5, name = function(info) return "Current: " .. info.handler:GetCurrentProfile() end },
      choose = { type = "select", order = 20, name = "Existing Profiles", get = "GetCurrentProfile", set = "SetProfile", values = "ListProfiles", arg = "common" },
      new = { type = "input", order = 30, name = "New", get = false, set = "SetProfile" },
      copyfrom = { type = "select", order = 40, name = "Copy From", get = false, set = "SetProfile", values = "ListProfiles", disabled = "HasNoProfiles", arg = "nocurrent" },
    } } end }
  libs["AceConfigDialog-3.0"] = { AddToBlizOptions = function() return {} end, Close = function() end }
  libs["AceGUI-3.0"] = { WidgetRegistry = {}, RegisterWidgetType = function(self, name, ctor) self.WidgetRegistry[name] = ctor end }
  libs["LibSharedMedia-3.0"] = { List = function() return { "Blizzard", "Nock Clean" } end, Fetch = function() return nil end, Register = function() return true end }
  libs["AceConfigRegistry-3.0"] = {
    GetOptionsTable = function(_, app, uiType, uiName)
      local f = function() return registered end
      if uiType then return f(uiType, uiName) end
      return f
    end,
    NotifyChange = function() notified = notified + 1 end,
    RegisterCallback = function(_, obj, evt, fn) callbacks[evt] = fn end,
  }
  _G.LibStub = setmetatable({}, { __call = function(_, name, silent)
    local lib = libs[name]
    if not lib and not silent then error("harness: missing lib " .. name) end
    return lib
  end })
  local Nock = {
    db = { profile = {}, global = {}, char = {} },
    Constants = setmetatable({}, { __index = function(t, k) local v = {}; rawset(t, k, v); return v end }),
    UI = {},
  }
  local STUB_CATALOGS = opts.catalogs or {
    Warnings = { Catalog = {
      { key = "test1", name = "Test Warning", enabledKey = "warnTest1", category = "pet", severity = "red",
        description = "Stub warning.", logic = "Never (harness only).",
        thresholds = { { key = "thTest1", label = "Threshold", min = 0, max = 10, step = 1 } } },
    } },
    Helpers = { Catalog = { { key = "htest1", name = "Test Helper", enabledKey = "helpTest1", description = "Stub helper.", logic = "Never." } } },
  }
  Nock.db.profile = opts.profile or {}
  function Nock:GetModule(name) return STUB_CATALOGS[name] end
  function Nock:SendMessage() end
  function Nock.IsLocked() return true end
  -- What Options.lua's name/get functions reach for at build time.
  Nock.state = { sim = {}, ranged = {}, player = {} }
  Nock.UI.ResolveReactBarOrder = function(stored) return stored or { "auto", "melee", "range", "mana" } end
  Nock.UI.ResolveFluffyBarOrder = function(stored) return stored or { "swing", "ranged", "melee", "range", "mana" } end
  _G.NockStub = Nock
  -- the real constants (a plain table literal): min/max/step read numbers, as in the client
  dofile("Core/Constants.lua")
  dofile("Config/Options.lua")
  local fa = io.open("Config/OptionsAdvanced.lua"); if fa then fa:close(); dofile("Config/OptionsAdvanced.lua") end
  local fl = io.open("Config/OptionsLayout.lua"); if fl then fl:close(); dofile("Config/OptionsLayoutData.lua"); dofile("Config/OptionsLayout.lua") end
  local fp = io.open("Config/Presets.lua"); if fp then fp:close(); dofile("Config/Presets.lua") end
  dofile("UI/AceGUI_LSMDropdown.lua")
  dofile("Core/OptionsWalk.lua")
  Nock:RegisterOptions()
  Nock._harness = { notified = function() return notified end, callbacks = callbacks }
  return Nock, Nock.OptionsWalk, registered
end
