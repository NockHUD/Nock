-- Tests/tracker_missing_highlight_test.lua
-- Standalone LuaJIT tests for the buff/debuff grids' own "missing" highlight
-- style. The grids used to borrow Rotation -> Next-action highlight wholesale
-- (effect + colour), so restyling the next-action glow recoloured every
-- missing-buff border with it, and the only control over that border sat
-- three tabs away. Each grid now carries its own effect/colour, resolved by
-- Nock.UI.MissingHighlightStyle, with "none" as the baseline (user,
-- 2026-09-07): the greyed icon says missing, the border is opt-in.
-- Run from the repo root: luajit Tests/tracker_missing_highlight_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end

local Nock = {
  db = { profile = {} },
  Constants = setmetatable({}, {
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
Nock.Constants.COLORS.NEXT_HIGHLIGHT = { 0, 1, 0.4, 1 }

local P = Nock.db.profile
local function same(c, r, g, b, a)
  return type(c) == "table" and c[1] == r and c[2] == g and c[3] == b and (c[4] or 1) == a
end

-- 1. The grid's own pair; the rotation's next-action setting plays no part.
P.rotNextEffect = "buttonGlow"
P.rotNextColor = { 1, 0, 0, 1 }
P.buffTrackerMissingEffect = "static"
P.buffTrackerMissingColor = { 0, 0, 1, 1 }
local e, c = Nock.UI.MissingHighlightStyle("buffTracker")
ok(e == "static" and same(c, 0, 0, 1, 1), "the grid's own effect and colour")
P.rotNextEffect = "none"
e, c = Nock.UI.MissingHighlightStyle("buffTracker")
ok(e == "static" and same(c, 0, 0, 1, 1), "...untouched by the rotation's next-action setting")

-- 2. The two grids are separate keys.
P.debuffTrackerMissingEffect = "pixelGlow"
P.debuffTrackerMissingColor = { 0, 1, 0, 0.5 }
e, c = Nock.UI.MissingHighlightStyle("debuffTracker")
ok(e == "pixelGlow" and same(c, 0, 1, 0, 0.5), "the debuff grid has its own pair")
e, c = Nock.UI.MissingHighlightStyle("buffTracker")
ok(e == "static" and same(c, 0, 0, 1, 1), "...and the buff grid keeps its own")

-- 3. Unset keys (a profile from before the setting): no effect, and a colour
--    that is never nil (a nil colour is what makes AceConfigDialog's build
--    loop abort) -- the next-action green stands in.
P.buffTrackerMissingEffect = nil
P.buffTrackerMissingColor = nil
e, c = Nock.UI.MissingHighlightStyle("buffTracker")
ok(e == "none", "unset effect reads as none (the baseline)")
ok(same(c, 0, 1, 0.4, 1), "unset colour falls back to the next-action green, never nil")

-- 4. "None" leaves the slot unlit without touching the rotation slot:
--    SetIconNextHighlight honours the effect override.
local applied = {}
Nock.UI.SetIconHighlight = function(slot, color) applied[#applied + 1] = color and "on" or "off" end
local slot = { glow = { Show = function() end, Hide = function() end, SetBackdropBorderColor = function() end } }
P.buffTrackerMissingColor = { 0, 0, 1, 1 }
Nock.UI.SetIconMissingHighlight(slot, true, "buffTracker")
ok(slot._nockNextSig == "off", "grid effect none: the slot is left unlit (sig off)")
P.buffTrackerMissingEffect = "static"
Nock.UI.SetIconMissingHighlight(slot, true, "buffTracker")
ok(slot._nockNextSig ~= "off" and slot._nockNextSig:find("^static|"), "grid effect static: drawn as a static border")
ok(applied[#applied] == "on", "  ... through SetIconHighlight")
Nock.UI.SetIconMissingHighlight(slot, false, "buffTracker")
ok(slot._nockNextSig == "off", "off clears it")

-- 5. The rotation slot's own call is unchanged by the new argument.
P.rotNextEffect = "static"
Nock.UI.SetIconNextHighlight(slot, true)
ok(slot._nockNextSig:find("^static|1%.000/0%.000/0%.000/1%.000|2$"), "SetIconNextHighlight without overrides: rotation effect, colour, thickness 2")

-- 6. Defaults exist for every key both option pages read (nil get() aborts
--    the AceConfigDialog build loop silently), and there is no Follow key.
dofile("Config/Defaults.lua")
local D = Nock.Defaults.profile
for _, prefix in ipairs({ "buffTracker", "debuffTracker" }) do
  ok(D[prefix .. "MissingFollow"] == nil, prefix .. "MissingFollow does not exist")
  ok(D[prefix .. "MissingEffect"] == "none", prefix .. "MissingEffect defaults to none")
  ok(same(D[prefix .. "MissingColor"], 0, 1, 0.4, 1), prefix .. "MissingColor defaults to the next-action green")
end

print(string.format("tracker_missing_highlight: %d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
