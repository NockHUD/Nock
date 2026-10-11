-- Tests/client_font_string_test.lua
-- A FontString handed to a Forever aura button (the sting tiles' countdown)
-- is the client's: once it has shown a secret it is forbidden to tainted
-- code and SetFont throws. The media refresh must try it and accept a
-- refusal, never raise (EotB exit after a kill, 2026-10-11).
-- Run from the repo root: luajit Tests/client_font_string_test.lua

local pass, fail = 0, 0
local function ok(c, n) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. n) end end

local Nock = {
  db = { profile = {} },
  Constants = setmetatable({ FONT = { PATH = "base.ttf", SIZE_OVERLAY = 10 } }, {
    __index = function(t, k) local v = {}; rawset(t, k, v); return v end,
  }),
}
local libs = { ["AceAddon-3.0"] = { GetAddon = function() return Nock end } }
_G.LibStub = setmetatable({}, {
  __call = function(_, name, silent)
    local lib = libs[name]
    if not lib and not silent then error("harness: missing lib " .. name) end
    return lib
  end,
})
_G.CreateFrame = function()
  local f = {}
  function f:RegisterEvent() end
  function f:SetScript() end
  return f
end

dofile("UI/Widgets.lua")
local UI = Nock.UI
UI.GetFont = function() return "face.ttf" end
UI.GetReactFont = function() return nil end
UI.GetReactCdFontSize = function() return 12 end
UI.GetReactFontStyle = function() return "OUTLINE" end
UI.ApplyReactTextShadow = function() end
UI.RefreshBarStyles = function() end

local function fontString(forbidden, throws)
  local fs = { fonts = 0 }
  function fs:IsForbidden() return forbidden end
  function fs:SetFont()
    if throws then error("calling 'SetFont' on bad self (Attempt to access forbidden object from code tainted by an AddOn)") end
    self.fonts = self.fonts + 1
    return true
  end
  function fs:GetText() return nil end
  function fs:SetText() end
  return fs
end

local plain = fontString(false, false)
local forbidden = fontString(true, true)
local refusing = fontString(false, true)   -- refuses without reporting forbidden
local owned = fontString(false, false)
UI.RegisterFontString(plain, "SIZE_OVERLAY", "OUTLINE", true)
UI.RegisterClientFontString(forbidden, "SIZE_OVERLAY", "OUTLINE", true)
UI.RegisterClientFontString(refusing, "SIZE_OVERLAY", "OUTLINE", true)
UI.RegisterClientFontString(owned, "SIZE_OVERLAY", "OUTLINE", true)

local okr, err = pcall(UI.RefreshMedia)
ok(okr, "media refresh survives a forbidden client string (" .. tostring(err) .. ")")
ok(plain.fonts > 0, "an ordinary string is restyled")
ok(owned.fonts > 0, "a client string that accepts is restyled")
ok(forbidden.fonts == 0, "a forbidden client string is left alone")

print(("client_font_string: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
