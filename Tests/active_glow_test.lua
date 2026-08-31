-- Tests/active_glow_test.lua
-- Standalone LuaJIT tests for the per-HUD active-highlight styling: the
-- ReactSlotLook activeStyle lever, ApplyGlowStyle geometry (overflow vs
-- contained), and the per-HUD default keys.
-- Run from the repo root: luajit Tests/active_glow_test.lua
--
-- The "blue border" people asked to restyle is C.COLORS.PROC_GLOW drawn by
-- SetIconHighlight while procActive. Each HUD family now carries its own
-- Style / Color / Size / Fit set; the KC-only reactKcProcGlow override
-- outranks the grid-wide style on the KC slot.

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
dofile("Config/Defaults.lua")

--------------------------------------------------------------------------------
-- §1 Defaults: four keys per HUD family, shipping at today's look.
--------------------------------------------------------------------------------
local D = Nock.Defaults.profile
local CYAN = { 0.00, 0.90, 0.90, 1.00 }
local function eqColor(a, b)
  return type(a) == "table"
     and a[1] == b[1] and a[2] == b[2] and a[3] == b[3] and a[4] == b[4]
end
for _, prefix in ipairs({ "cooldownActive", "reactActive", "fluffyActive" }) do
  ok(D[prefix .. "Style"] == "border", prefix .. "Style defaults to border")
  ok(eqColor(D[prefix .. "Color"], CYAN), prefix .. "Color defaults to the PROC_GLOW cyan")
  ok(D[prefix .. "Size"] == 3, prefix .. "Size defaults to 3")
  ok(D[prefix .. "Fit"] == "overflow", prefix .. "Fit defaults to overflow")
end

--------------------------------------------------------------------------------
-- §2 ReactSlotLook: opts.activeStyle decides the proc look; opts.procGlow
-- (the KC-only override) outranks it.
--------------------------------------------------------------------------------
local Look = Nock.UI.ReactSlotLook
ok(type(Look) == "function", "ReactSlotLook exists")

local proc = { procActive = true }
ok(Look(proc, nil, {}).glow == "border", "proc with no style opts -> border (today's look)")
ok(Look(proc, nil, { activeStyle = "border" }).glow == "border", "activeStyle border -> border")
ok(Look(proc, nil, { activeStyle = "glow" }).glow == "overlay", "activeStyle glow -> overlay")
ok(Look(proc, nil, { activeStyle = "none" }).glow == nil, "activeStyle none -> no glow")
ok(Look(proc, nil, { activeStyle = "none", procGlow = true }).glow == "overlay",
   "KC override wins over activeStyle none")
ok(Look(proc, nil, { activeStyle = "border", procGlow = true }).glow == "overlay",
   "KC override wins over activeStyle border")
ok(Look({ ready = true }, nil, { activeStyle = "glow" }).glow == nil,
   "a ready (non-proc) tile never glows, whatever the style")

-- opts.preview (the settings' preview toggle) forces the ACTIVE look onto any
-- tile so the style can be dialed in without waiting for a real proc.
ok(Look({ ready = true }, nil, { preview = true }).glow == "border",
   "preview forces the active border onto a ready tile")
ok(Look({ remaining = 30 }, nil, { preview = true, activeStyle = "glow" }).glow == "overlay",
   "preview respects the chosen style on a cooling tile")
ok(Look({ ready = true }, nil, { preview = true }).vis == "proc",
   "preview reads as the proc vis state")

-- The look key must distinguish the styles, or a style flip on a lit slot
-- would be swallowed by the painter's change guard.
local K = Nock.UI.ReactLookKey
ok(K(Look(proc, nil, { activeStyle = "glow" })) ~= K(Look(proc, nil, { activeStyle = "none" })),
   "look key separates overlay from none")

--------------------------------------------------------------------------------
-- §3 ApplyGlowStyle geometry: overflow hangs size px outside the slot,
-- contained draws inside the slot's own bounds. Backdrop edge follows size.
--------------------------------------------------------------------------------
local Apply = Nock.UI.ApplyGlowStyle
ok(type(Apply) == "function", "ApplyGlowStyle exists")

local function stubGlow()
  local g = { points = {}, backdrop = nil }
  function g:ClearAllPoints() self.points = {} end
  function g:SetPoint(point, _, _, x, y) self.points[point] = { x = x, y = y } end
  function g:SetBackdrop(b) self.backdrop = b end
  function g:SetBackdropColor() end
  function g:SetBackdropBorderColor() end
  function g:Hide() end
  return g
end

local slot = { glow = stubGlow() }
Apply(slot, 2, false)
ok(slot.glow.points.TOPLEFT and slot.glow.points.TOPLEFT.x == -2
   and slot.glow.points.TOPLEFT.y == 2, "overflow: TOPLEFT hangs size px out")
ok(slot.glow.points.BOTTOMRIGHT and slot.glow.points.BOTTOMRIGHT.x == 2
   and slot.glow.points.BOTTOMRIGHT.y == -2, "overflow: BOTTOMRIGHT hangs size px out")
ok(slot.glow.backdrop and slot.glow.backdrop.edgeSize == 2, "overflow: edgeSize == size")

Apply(slot, 4, true)
ok(slot.glow.points.TOPLEFT.x == 0 and slot.glow.points.TOPLEFT.y == 0,
   "contained: TOPLEFT on the slot's own corner")
ok(slot.glow.points.BOTTOMRIGHT.x == 0 and slot.glow.points.BOTTOMRIGHT.y == 0,
   "contained: BOTTOMRIGHT on the slot's own corner")
ok(slot.glow.backdrop.edgeSize == 4, "contained: edgeSize == size")

-- A slot without a glow frame is a no-op, not an error (Warnings' contract).
ok(pcall(Apply, {}, 3, false), "no glow frame -> silent no-op")

--------------------------------------------------------------------------------
print(("active_glow_test: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
