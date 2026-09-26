-- Tests/blizz_castbar_hide_test.lua
-- Nock.UI.SetBlizzardCastBarHidden (UI/Widgets.lua): hide Blizzard's player
-- cast bar, keep it hidden if the client shows it again, restore only what
-- was hidden. Shared by the TBC and Forever cast bar modules.
-- Run from the repo root: luajit Tests/blizz_castbar_hide_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. name) end
end

local Nock = {
  db = { profile = {} },
  Constants = setmetatable({}, { __index = function(t, k) local v = {}; rawset(t, k, v); return v end }),
}
local libs = { ["AceAddon-3.0"] = { GetAddon = function() return Nock end } }
_G.LibStub = setmetatable({}, { __call = function(_, name, silent)
  local lib = libs[name]
  if not lib and not silent then error("harness: missing lib " .. name) end
  return lib
end })
_G.CreateFrame = function()
  local f = {}
  function f:RegisterEvent() end
  function f:SetScript() end
  return f
end
dofile("UI/Widgets.lua")
local Hide = Nock.UI.SetBlizzardCastBarHidden
ok(type(Hide) == "function", "helper exists")
ok(Hide(true) == true, "no Blizzard bar on this client: nothing to do")

-- A modern client's bar: OnLoad on the mixin, OnShow hookable.
local bar = { shown = true, events = true, loads = 0, hooks = {} }
function bar:UnregisterAllEvents() self.events = false end
function bar:Hide() self.shown = false end
function bar:Show() self.shown = true; for _, fn in ipairs(self.hooks) do fn(self) end end
function bar:HookScript(k, fn) if k == "OnShow" then self.hooks[#self.hooks + 1] = fn end end
function bar:OnLoad() self.loads = self.loads + 1; self.events = true end
_G.PlayerCastingBarFrame = bar

ok(Hide(false) == true and bar.loads == 0, "nothing hidden yet: restore never pokes the bar")
ok(Hide(true) == true and bar.shown == false and bar.events == false, "hidden: events dropped, frame hidden")
bar:Show()
ok(bar.shown == false, "the client shows it again (Edit Mode): the guard hides it")
Hide(true)
ok(#bar.hooks == 1, "the guard is hooked once")
ok(Hide(false) == true and bar.loads == 1 and bar.events == true, "restored through the bar's own OnLoad")
bar:Show()
ok(bar.shown == true, "restored: the guard lets it show")

-- An older client: the Classic-era global OnLoad.
local old = { shown = true, hooks = {} }
function old:UnregisterAllEvents() end
function old:Hide() self.shown = false end
function old:HookScript(k, fn) self.hooks[#self.hooks + 1] = fn end
_G.PlayerCastingBarFrame, _G.CastingBarFrame = nil, old
local args
_G.CastingBarFrame_OnLoad = function(f, unit, trade, shield) args = { f, unit, trade, shield } end
Hide(true)
ok(Hide(false) == true and args and args[1] == old and args[2] == "player" and args[3] == true and args[4] == false, "Classic-era restore: CastingBarFrame_OnLoad(frame, 'player', true, false)")
_G.CastingBarFrame_OnLoad = nil
Hide(true)
ok(Hide(false) == false, "no OnLoad anywhere: false (the caller says /reload)")

print(("blizz_castbar_hide: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
