-- UI/Widgets.lua
-- Shared widget builders: backdrop frames, horizontal bars, icon slots.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local C = Nock.Constants
Nock.UI = Nock.UI or {}

local SOLID_TEX = "Interface\\Buttons\\WHITE8X8"
local DEFAULT_BAR_TEX = "Interface\\TargetingFrame\\UI-StatusBar"

local LSM = LibStub("LibSharedMedia-3.0", true)

-- Nock's own bar texture, shipped in Media/ and registered here so the default
-- look is identical for EVERY user with no dependency on another addon.
--
-- Why we ship one at all: LibSharedMedia's built-in statusbar list is just
-- Blizzard / Blizzard Character Skills Bar / Blizzard Raid Bar / Solid. Every
-- other name in that dropdown — including the popular "Clean" (registered by
-- WeakAuras) — comes from whatever else the user happens to have installed. And
-- LSM:Fetch silently falls back to the Blizzard texture for an unregistered
-- name rather than erroring, so defaulting to a borrowed name would leave
-- anyone without that addon quietly looking at a different HUD.
--
-- Registered under our own name, NOT "Clean": lib:Register overwrites by key, so
-- claiming "Clean" would clobber WeakAuras' (or be clobbered by it, depending on
-- load order) and make the dropdown mean two different things.
--
-- Registered at file load, which is before any frame is built (UI/Widgets.lua
-- precedes every UI/Frame_* in the .toc), so the first Fetch already resolves.
local NOCK_CLEAN = "Nock Clean"
if LSM then
  LSM:Register("statusbar", NOCK_CLEAN, [[Interface\AddOns\Nock\Media\NockClean]])
end

-- Registries of media-consuming widgets for live-refresh via RefreshMedia.
local barFills, fontStrings, iconSlots = {}, {}, {}
-- Header FontStrings that want a SPECIFIC named LSM font (e.g. "Numen") rather
-- than the global profile font. SharedMedia plugin addons (which register the
-- named fonts) may load AFTER Nock — on the cold-load tick `LSM:Fetch(name)`
-- returns nil and the header initially renders with a fallback. We track these
-- FS so we can re-apply once the named font finally registers (see the
-- LibSharedMedia_Registered callback below) — that's the cold-load race the
-- "headers blank until /reload" bug came from.
local headerFontStrings = {}

local function profile(key, fallback)
  local p = Nock.db and Nock.db.profile and Nock.db.profile[key]
  if p ~= nil then return p end
  return fallback
end

function Nock.UI.GetBarTexture()
  local name = profile("barTexture", NOCK_CLEAN)
  if LSM and name then
    local path = LSM:Fetch("statusbar", name)
    if path then return path end
  end
  return DEFAULT_BAR_TEX
end

-- Resolve a per-bar texture override stored under profile[key]. A non-empty LSM
-- statusbar name wins; "" / nil / an unknown name falls back to the global
-- barTexture. Used so individual bars (e.g. the swing bars) can opt out of the
-- single global texture without breaking the live-refresh path in RefreshMedia.
function Nock.UI.GetBarTextureFor(key)
  local name = key and profile(key, nil)
  if name and name ~= "" and LSM then
    local path = LSM:Fetch("statusbar", name)
    if path then return path end
  end
  return Nock.UI.GetBarTexture()
end

function Nock.UI.GetFont()
  local name = profile("fontFace", "Friz Quadrata TT")
  if LSM and name then
    local path = LSM:Fetch("font", name)
    if path then return path end
  end
  return C.FONT.PATH
end

-- React-scoped media (React HUD tab → Skin). "" — the default — means the
-- fixed reference skin, so unlike GetBarTextureFor these do NOT fall back to
-- the global barTexture/fontFace: they return nil and each caller `or`s in
-- its hardcoded reference value (WHITE8X8 fills / C.FONT.PATH text). The one
-- exception is the React CD grid, whose text follows the GLOBAL font when
-- reactFont is unset (it always has — see the react flag in RefreshMedia).
function Nock.UI.GetReactBarTexture()
  local name = profile("reactBarTexture", "")
  if name and name ~= "" and LSM then
    local path = LSM:Fetch("statusbar", name)
    if path then return path end
  end
  return nil
end

function Nock.UI.GetReactFont()
  local name = profile("reactFont", "")
  if name and name ~= "" and LSM then
    local path = LSM:Fetch("font", name)
    if path then return path end
  end
  return nil
end

-- User font-size nudge for React text. reactFontSize (default 9 — the
-- reference FONT_BIG) is exposed to callers as a DELTA against that
-- reference, so every React string keeps its relative proportions: small
-- labels stay 2 under big, slot text keeps tracking the slot edge, grid text
-- shifts off its own overlay size. Callers clamp to >= 6 after adding.
function Nock.UI.GetReactFontDelta()
  local v = tonumber(profile("reactFontSize", 9)) or 9
  return v - 9
end

-- Resolve the icon-slot border from the active profile + LSM. "None" (or an
-- unregistered name) maps to a 1px solid line — the original Nock look. LSM
-- borders are typically 16x16 textures that need edgeSize ~8 to render
-- properly; iconBorderSize is exposed as a setting for fine-tuning.
local function getIconBorderInfo()
  local name = profile("iconBorder", "None")
  if name and name ~= "None" and name ~= "" and LSM then
    local edge = LSM:Fetch("border", name, true)
    if edge and edge ~= "" then
      local sz = profile("iconBorderSize", 8)
      return edge, sz, sz + 1
    end
  end
  return SOLID_TEX, 1, 2
end

-- HUD backdrop border, mirroring getIconBorderInfo but driven by the hudBorder /
-- hudBorderSize profile keys. "None" (or unregistered) = the original 1px solid
-- box. LSM borders inset the fill by their edge size so it can't bleed over them.
local function getHudBorderInfo()
  local name = profile("hudBorder", "None")
  if name and name ~= "None" and name ~= "" and LSM then
    local edge = LSM:Fetch("border", name, true)
    if edge and edge ~= "" then
      local sz = profile("hudBorderSize", 12)
      return edge, sz, sz
    end
  end
  return SOLID_TEX, 1, 1
end

-- Rebuilds a frame's backdrop edge from the active hudBorder setting. Colors are
-- applied separately by the caller (HUD:ApplyBackground) since SetBackdrop resets
-- them. Used for the top-level HUD frame only — bars/panels keep the 1px solid.
function Nock.UI.ApplyHudBackdrop(frame)
  local edge, edgeSize, inset = getHudBorderInfo()
  frame:SetBackdrop({
    bgFile   = SOLID_TEX,
    edgeFile = edge,
    edgeSize = edgeSize,
    insets   = { left = inset, right = inset, top = inset, bottom = inset },
  })
end

-- Glued side/edge panels (totem, pet status, repair) are meant to read as one
-- seamless box with the HUD, so their backdrop must MATCH the HUD background
-- styling (fill + border) — otherwise turning the HUD background off leaves
-- these panels as orphaned black boxes. They register here and get repainted
-- whenever HUD:ApplyBackground runs (RefreshPanelBackgrounds).
local panelBackdrops = {}

function Nock.UI.ApplyPanelBackground(frame)
  Nock.UI.ApplyHudBackdrop(frame)  -- same edge texture/size as the HUD
  local p = Nock.db and Nock.db.profile or {}
  if p.backgroundEnabled == false then
    frame:SetBackdropColor(0, 0, 0, 0)
    frame:SetBackdropBorderColor(0, 0, 0, 0)
    return
  end
  local c = p.backgroundColor or { 0, 0, 0 }
  local a = p.backgroundOpacity
  if a == nil then a = 0.85 end
  frame:SetBackdropColor(c[1] or 0, c[2] or 0, c[3] or 0, a)
  local bc = p.hudBorderColor or { 0, 0, 0 }
  local ba = p.hudBorderOpacity
  if ba == nil then ba = 1.0 end
  frame:SetBackdropBorderColor(bc[1] or 0, bc[2] or 0, bc[3] or 0, ba)
end

function Nock.UI.RegisterPanelBackground(frame)
  panelBackdrops[#panelBackdrops + 1] = frame
  Nock.UI.ApplyPanelBackground(frame)
end

function Nock.UI.RefreshPanelBackgrounds()
  for i = 1, #panelBackdrops do
    if panelBackdrops[i] then Nock.UI.ApplyPanelBackground(panelBackdrops[i]) end
  end
end

-- The practice windows carry their own scale: they are teaching surfaces read
-- at arm's length, not HUD chrome, and every size in them is a UI unit at the
-- frame's own scale. One slider (`practiceScale`) drives all five through
-- SetScale on the top-level frame -- children inherit, which is why the docked
-- stage is NOT registered here (it is a child of the panel while docked and
-- would otherwise be scaled twice; UI/Frame_PracticeConveyor.lua sets its own
-- from ApplyDock, 1 docked and the slider's value floating).
-- The default is 1.0 (user, 2026-08-27) and the slider reaches 3.0: a 4K
-- screen with the UI scale off is 2160 units tall, and the old 1.5 ceiling
-- kept the windows at half the size they have on a 1440p screen.
local PRACTICE_SCALE_MIN, PRACTICE_SCALE_MAX, PRACTICE_SCALE_DEFAULT = 0.75, 3.0, 1.0
local practiceScaled = {}

-- Scale a registered window and keep it where it is on screen: a SetPoint
-- offset is in the frame's OWN scale units, so a new scale would otherwise
-- walk the window away from where it was dropped.
local function rescale(f, s)
  local old = f:GetScale() or 1
  local point, rel, relPoint, x, y = f:GetPoint()
  f:SetScale(s)
  if point and old > 0 and old ~= s then
    f:ClearAllPoints()
    f:SetPoint(point, rel, relPoint, (x or 0) * old / s, (y or 0) * old / s)
  end
end

function Nock.UI.PracticeScale()
  local v = Nock.db and Nock.db.profile and Nock.db.profile.practiceScale
  if type(v) ~= "number" then return PRACTICE_SCALE_DEFAULT end
  if v < PRACTICE_SCALE_MIN then return PRACTICE_SCALE_MIN end
  if v > PRACTICE_SCALE_MAX then return PRACTICE_SCALE_MAX end
  return v
end

-- Register a top-level practice window and scale it now. Insecure frames only:
-- SetScale on one is unprotected, so there is no combat guard here.
function Nock.UI.RegisterPracticeScale(frame)
  if not frame then return end
  practiceScaled[#practiceScaled + 1] = frame
  frame:SetScale(Nock.UI.PracticeScale() * (frame._scaleFit or 1))
end

-- A window's own fit factor on top of the slider (the workbench caps itself
-- to the screen, UI/Frame_Workbench.lua): 1 = the slider's value. Re-scales
-- the window in place.
function Nock.UI.SetPracticeScaleFit(frame, fit)
  if not frame then return end
  frame._scaleFit = fit or 1
  rescale(frame, Nock.UI.PracticeScale() * frame._scaleFit)
end

-- Re-scale every registered window, each keeping its place on screen. Called
-- from the Options slider and from HUD:ApplyBackground, so a profile switch
-- reaches all five windows.
function Nock.UI.ApplyPracticeScale()
  local s = Nock.UI.PracticeScale()
  if s <= 0 then return end
  for i = 1, #practiceScaled do
    local f = practiceScaled[i]
    if f then rescale(f, s * (f._scaleFit or 1)) end
  end
end

-- Undo the screen seed (2026-08-27, three revisions in one day, all on the
-- weave-practice branch): it read UIParent's height from HUD:ApplyBackground
-- at login, where the client had not applied the UI scale yet (768 units,
-- whatever the screen), and wrote the slider's floor -- "mine was at 75%
-- from start". A profile the seed touched goes back to the default; the
-- flag goes with it. The screen-fit cap (Workbench.FitScale) reads the
-- screen at relayout, where it is right.
function Nock.UI.RepairPracticeScale()
  local p = Nock.db and Nock.db.profile
  if not p or p.practiceScaleSeeded == nil then return end
  p.practiceScale = nil
  p.practiceScaleSeeded = nil
end

-- Per-panel user styling for the floating panels (MD tracker, buff/debuff
-- grids, shopping list). Reads the per-panel Background block written by
-- Config/Options.lua's panelStyleArgs: <prefix>BgColor / <prefix>BgOpacity
-- (or the explicit opacityKey — the MD tracker predates the block with
-- mdBackgroundOpacity) / <prefix>Border / <prefix>BorderSize /
-- <prefix>BorderColor / <prefix>BorderOpacity. "None" or an unregistered LSM
-- border name = the original 1px solid line. Callers re-run this on
-- NOCK_VISUALS_CHANGED / NOCK_LOCK_CHANGED and apply the BORDER_UNLOCK drag
-- cue AFTER it — the green outline must win over the user's border color
-- while repositioning. Touches only backdrop textures, so it is safe on a
-- protected frame in combat.
function Nock.UI.ApplyUserPanelStyle(frame, prefix, opacityKey)
  local edge, edgeSize, inset = SOLID_TEX, 1, 1
  local name = profile(prefix .. "Border", "None")
  if name and name ~= "None" and name ~= "" and LSM then
    local path = LSM:Fetch("border", name, true)
    if path and path ~= "" then
      edge = path
      edgeSize = profile(prefix .. "BorderSize", 12)
      inset = edgeSize
    end
  end
  frame:SetBackdrop({
    bgFile   = SOLID_TEX,
    edgeFile = edge,
    edgeSize = edgeSize,
    insets   = { left = inset, right = inset, top = inset, bottom = inset },
  })
  local c = profile(prefix .. "BgColor", nil) or C.COLORS.BG
  local a = profile(opacityKey or (prefix .. "BgOpacity"), nil)
  if a == nil then a = C.COLORS.BG[4] end
  frame:SetBackdropColor(c[1] or 0, c[2] or 0, c[3] or 0, a)
  local bc = profile(prefix .. "BorderColor", nil) or C.COLORS.BORDER
  local ba = profile(prefix .. "BorderOpacity", nil)
  if ba == nil then ba = 1.0 end
  frame:SetBackdropBorderColor(bc[1] or 0, bc[2] or 0, bc[3] or 0, ba)
end

-- Per-bar track (background) styling. Every classic bar is a 1px-backdrop frame
-- whose fill texture floats on top; the backdrop is what shows through wherever
-- the fill hasn't reached. It used to be hardcoded to C.COLORS.BG (black @0.85)
-- with a black border, which is the "everything is a black box" look. Each bar
-- now carries its own key prefix and reads four keys written by
-- Config/Options.lua's barStyleArgs: <prefix>BgColor / <prefix>BgOpacity /
-- <prefix>BorderColor / <prefix>BorderOpacity. An unset key falls back to the
-- old constants, so a profile that has never touched the block is pixel-identical.
--
-- Deliberately NOT an LSM border like ApplyUserPanelStyle: these are bars, some
-- only 4px tall (the GCD sweep), and a 12px edge texture would swallow them whole.
-- The 1px solid backdrop from ApplyBackdrop stays; only the colors move.
local barBackdrops = {}

function Nock.UI.ApplyBarStyle(frame, prefix)
  if not (frame and frame.SetBackdropColor and prefix) then return end
  local c = profile(prefix .. "BgColor", nil) or C.COLORS.BG
  local a = profile(prefix .. "BgOpacity", nil)
  if a == nil then a = C.COLORS.BG[4] end
  frame:SetBackdropColor(c[1] or 0, c[2] or 0, c[3] or 0, a)
  local bc = profile(prefix .. "BorderColor", nil) or C.COLORS.BORDER
  local ba = profile(prefix .. "BorderOpacity", nil)
  if ba == nil then ba = C.COLORS.BORDER[4] or 1.0 end
  frame:SetBackdropBorderColor(bc[1] or 0, bc[2] or 0, bc[3] or 0, ba)
end

-- Register a bar frame for live restyle. Applies once immediately so the bar is
-- correct on the very first frame, before any NOCK_VISUALS_CHANGED fires.
function Nock.UI.RegisterBarBackdrop(frame, prefix)
  if not (frame and prefix) then return end
  barBackdrops[#barBackdrops + 1] = { frame = frame, prefix = prefix }
  Nock.UI.ApplyBarStyle(frame, prefix)
end

-- Repaint every registered bar track. Called from RefreshMedia, which the
-- NOCK_VISUALS_CHANGED handler already runs — so an options change lands live.
function Nock.UI.RefreshBarStyles()
  for i = 1, #barBackdrops do
    local e = barBackdrops[i]
    if e and e.frame then Nock.UI.ApplyBarStyle(e.frame, e.prefix) end
  end
end

-- Register a bar fill for live texture refresh. An optional profile key lets the
-- fill carry a per-bar texture override (resolved in RefreshMedia); without one
-- it tracks the global barTexture as before.
function Nock.UI.RegisterBarFill(fill, key)
  barFills[#barFills + 1] = { fill = fill, key = key }
end

-- `reactScoped` marks a FontString that should prefer the React font
-- (reactFont) when one is set, falling back to the global fontFace when it
-- isn't — the React CD grid's behavior. Everything else always follows the
-- global font.
function Nock.UI.RegisterFontString(fs, sizeKey, style, reactScoped)
  fontStrings[#fontStrings + 1] = {
    fs = fs, sizeKey = sizeKey or "SIZE_OVERLAY", style = style or "OUTLINE",
    react = reactScoped and true or nil,
  }
end

-- Force a relayout pass after SetFont. WoW's FontString doesn't always
-- re-rasterize when the underlying font path changes mid-life: GetFont
-- correctly returns the new path, but the visible glyphs are still drawn from
-- the previous font (or blank if that font wasn't loaded yet at the time of
-- the initial SetFont). Re-applying the text kicks the layout — cheap, idempotent.
local function kickRelayout(fs)
  if not (fs and fs.GetText) then return end
  local t = fs:GetText()
  if t and t ~= "" then fs:SetText(t) end
end

-- Resolve a named LSM font + apply it to a FontString, cascading through
-- fallbacks until SetFont actually accepts a path. SetFont returns false when
-- the path is unusable (file missing, font engine couldn't open it); when
-- that happens the FontString stays BLANK until something else succeeds,
-- which is the "title not rendering" symptom. Checking the boolean and
-- cascading is the robust pattern. After a successful SetFont we kick the
-- layout via SetText so the change becomes visible (see kickRelayout).
local function setHeaderFont(entry)
  if not (entry.fs and entry.fs.SetFont) then return end

  -- 1) Requested LSM-named font (e.g. "Numen").
  if LSM and entry.lsmName then
    local path = LSM:Fetch("font", entry.lsmName)
    if path and entry.fs:SetFont(path, entry.size, entry.style) then
      kickRelayout(entry.fs); return
    end
  end

  -- 2) Profile-level fontFace (whatever the global "Font" dropdown points to).
  local path = Nock.UI.GetFont()
  if path and entry.fs:SetFont(path, entry.size, entry.style) then
    kickRelayout(entry.fs); return
  end

  -- 3) Hard fallback to the built-in Blizzard font — always present on disk,
  --    so this *must* succeed. If even this fails the FontString itself is
  --    bad; nothing more to try.
  entry.fs:SetFont(C.FONT.PATH, entry.size, entry.style)
  kickRelayout(entry.fs)
end

-- `onApply` is the caller's chance to re-paint anything SetFont clears. A
-- FontString's SHADOW does not survive a SetFont on this client, and the
-- re-applies below (the LSM cold-load callback, PLAYER_ENTERING_WORLD) land
-- long after the owner last painted -- so a look built on SetShadowColor /
-- SetShadowOffset would silently go out the first time a SharedMedia plugin
-- registers our face. Optional, called with the FontString after every apply,
-- and only the handful of callers that paint past the face need one.
local function applyHeaderFont(entry)
  setHeaderFont(entry)
  local after = entry.onApply
  if after then after(entry.fs) end
end

function Nock.UI.RegisterHeaderFontString(fs, lsmFontName, size, style, onApply)
  local entry = { fs = fs, lsmName = lsmFontName, size = size, style = style or "THICKOUTLINE",
                  onApply = onApply }
  headerFontStrings[#headerFontStrings + 1] = entry
  applyHeaderFont(entry)
end

local function refreshHeaderFontStrings()
  for _, e in ipairs(headerFontStrings) do applyHeaderFont(e) end
end

-- Safe SetFont: tries the given path, then C.FONT.PATH if that fails. Mirrors
-- the cascade in applyHeaderFont so a bad LSM path can never leave a
-- FontString blank. Also kicks a relayout via SetText (see kickRelayout) so a
-- mid-life font change actually re-rasterizes.
local function safeSetFont(fs, path, size, style)
  if not (fs and fs.SetFont) then return end
  if path and fs:SetFont(path, size, style) then kickRelayout(fs); return end
  fs:SetFont(C.FONT.PATH, size, style)
  kickRelayout(fs)
end
-- Exported for the React views, which apply their own (reactFont-resolved)
-- font outside the fontStrings registry but want the same bad-path cascade.
Nock.UI.SafeSetFont = safeSetFont

function Nock.UI.RefreshMedia()
  for _, e in ipairs(barFills) do
    if e.fill and e.fill.SetTexture then
      e.fill:SetTexture(Nock.UI.GetBarTextureFor(e.key))
    end
  end
  local fontPath = Nock.UI.GetFont()
  local reactFontPath = Nock.UI.GetReactFont()
  local reactDelta = Nock.UI.GetReactFontDelta()
  for _, e in ipairs(fontStrings) do
    local size = C.FONT[e.sizeKey] or C.FONT.SIZE_OVERLAY
    if e.react then size = math.max(6, size + reactDelta) end
    safeSetFont(e.fs, (e.react and reactFontPath) or fontPath, size, e.style)
  end
  refreshHeaderFontStrings()
  for _, slot in ipairs(iconSlots) do
    Nock.UI.ApplyIconBorder(slot)
  end
  Nock.UI.RefreshBarStyles()
end

-- When a SharedMedia plugin (e.g. FojjiCore, which registers "Numen") loads
-- AFTER our headers have already been created, re-apply so the header
-- switches from its fallback to the real font without a /reload.
--
-- Belt-and-suspenders: also re-apply on PLAYER_ENTERING_WORLD. By PEW all
-- enabled addons have finished file-loading, so every LSM:Register call has
-- happened — this catches any case where the LSM callback chain misses
-- (version mismatches between embedded copies, etc.). Cheap: it's one extra
-- SetFont per header per login.
if LSM and LSM.RegisterCallback then
  LSM.RegisterCallback(Nock.UI, "LibSharedMedia_Registered", function(_, mediatype)
    if mediatype == "font" then refreshHeaderFontStrings() end
  end)
end

do
  local f = CreateFrame("Frame")
  f:RegisterEvent("PLAYER_ENTERING_WORLD")
  f:RegisterEvent("PLAYER_LOGIN")
  f:SetScript("OnEvent", function() refreshHeaderFontStrings() end)
end

-- Internal: dump the header-font registry so we can verify the cold-load race
-- is resolved. Each entry should show a path with "Numen" in it post-login if
-- FojjiCore is loaded. Surfaced via `/nock fonts` (copy window).
function Nock.UI._DumpHeaderFonts()
  local stamp = (date and date("%H:%M:%S")) or tostring(GetTime())
  local fcLoaded = "?"
  local chk = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
  if chk then fcLoaded = chk("FojjiCore") and "yes" or "no" end
  local lsmNumen = LSM and (LSM:Fetch("font", "Numen", true)) or nil  -- noDefault=true → real nil if missing
  local lines = {
    ("Nock /nock fonts @%s"):format(stamp),
    ("  FojjiCore loaded: %s     LSM has 'Numen' registered: %s")
      :format(fcLoaded, tostring(lsmNumen ~= nil)),
    ("  LSM:Fetch('font','Numen') -> %s"):format(tostring(lsmNumen)),
    "  Headers (per registered FontString):",
  }
  for i, e in ipairs(headerFontStrings) do
    local cur = (e.fs and e.fs.GetFont) and (e.fs:GetFont()) or "<nil>"
    local resolved = LSM and e.lsmName and LSM:Fetch("font", e.lsmName) or "<no-LSM>"
    lines[#lines + 1] = ("    [%d] want=%s size=%s style=%s"):format(
      i, tostring(e.lsmName), tostring(e.size), tostring(e.style))
    lines[#lines + 1] = ("        current  = %s"):format(tostring(cur))
    lines[#lines + 1] = ("        LSM:Fetch= %s"):format(tostring(resolved))
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "Interpretation:"
  lines[#lines + 1] = "  - current ends in Numen.ttf      -> font correct"
  lines[#lines + 1] = "  - current ends in FRIZQT__.TTF but LSM:Fetch shows Numen.ttf -> re-apply not running (bug in callback chain)"
  lines[#lines + 1] = "  - both end in FRIZQT__.TTF       -> FojjiCore not loaded (or Numen not registered)"
  return table.concat(lines, "\n")
end

-- Shared copyable text window. Single instance, reused — call with any block
-- of text and it shows, focuses, and selects-all so Ctrl+C works immediately.
-- Same shape as Modules/RangeFinder.lua's local copy window, hoisted here so
-- other diagnostics can share it.
local copyBox
function Nock.UI.ShowCopyBox(text)
  if not copyBox then
    local f = CreateFrame("Frame", "NockCopyBox", UIParent, "BackdropTemplate")
    f:SetSize(620, 380)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    Nock.UI.ApplyBackdrop(f)

    local sf = CreateFrame("ScrollFrame", "NockCopyBoxScroll", f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 14, -14)
    sf:SetPoint("BOTTOMRIGHT", -34, 44)
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFontObject(_G.ChatFontNormal or _G.GameFontHighlightSmall)
    eb:SetWidth(560)
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    sf:SetScrollChild(eb)
    f.eb = eb

    local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    close:SetSize(90, 22)
    close:SetPoint("BOTTOMRIGHT", -14, 12)
    close:SetText("Close")
    close:SetScript("OnClick", function() f:Hide() end)

    copyBox = f
  end
  copyBox.eb:SetText(text or "")
  local _, nl = tostring(text or ""):gsub("\n", "\n")
  copyBox.eb:SetHeight(math.max(320, (nl + 2) * 14))
  copyBox:Show()
  copyBox.eb:SetFocus()
  copyBox.eb:HighlightText()
  copyBox.eb:SetCursorPosition(0)
end

-- Re-applies the current iconBorder profile setting to an existing slot. Used
-- both at slot creation and from RefreshMedia when settings change. Updates
-- the slot's backdrop AND the icon's anchor (thicker borders eat more inset).
function Nock.UI.ApplyIconBorder(slot)
  -- Fixed-skin slots (React grid) keep their hardcoded 1px border; RefreshMedia
  -- re-applies the profile border to every registered slot, so opt out here.
  if slot._fixedBorder then return end
  local edge, edgeSize, iconInset = getIconBorderInfo()
  slot:SetBackdrop({
    bgFile   = SOLID_TEX,
    edgeFile = edge,
    edgeSize = edgeSize,
    insets   = { left = edgeSize, right = edgeSize, top = edgeSize, bottom = edgeSize },
  })
  slot:SetBackdropColor(unpack(C.COLORS.BG))
  slot:SetBackdropBorderColor(unpack(C.COLORS.BORDER))
  if slot.icon then
    slot.icon:ClearAllPoints()
    slot.icon:SetPoint("TOPLEFT",     slot, "TOPLEFT",     iconInset, -iconInset)
    slot.icon:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -iconInset, iconInset)
  end
end

local backdrop = {
  bgFile   = SOLID_TEX,
  edgeFile = SOLID_TEX,
  edgeSize = 1,
  insets   = { left = 1, right = 1, top = 1, bottom = 1 },
}

-- A panel's close control, as a TEXTURE rather than a glyph. Every text drawn
-- in a Nock panel goes through the user's LibSharedMedia font, and most of the
-- popular ones (Numen among them) carry no U+2715 — the review window's close
-- button rendered as an empty box for anyone not on the default face. Blizzard's
-- UIPanelCloseButton has no font in it at all, so it cannot go wrong; the
-- scenarios window has used it since it was built.
--
-- `size` is the box, not the artwork: the template's texture carries its own
-- transparent margin, so a 24 px button reads as a slightly smaller X.
function Nock.UI.CloseButton(parent, size, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelCloseButton")
  b:SetSize(size or 24, size or 24)
  if onClick then b:SetScript("OnClick", onClick) end
  return b
end

function Nock.UI.ApplyBackdrop(frame, bgColor, borderColor)
  frame:SetBackdrop(backdrop)
  frame:SetBackdropColor(unpack(bgColor or C.COLORS.BG))
  frame:SetBackdropBorderColor(unpack(borderColor or C.COLORS.BORDER))
end

-- textureKey (optional): a profile key holding a per-bar LSM texture override.
-- "" / nil in that profile field → the bar uses the global barTexture.
-- styleKey (optional): a key PREFIX for this bar's track styling block (see
-- ApplyBarStyle). Omit it and the bar keeps the hardcoded black backdrop.
function Nock.UI.CreateBar(parent, name, width, height, fillColor, textureKey, styleKey)
  local f = CreateFrame("Frame", name, parent, "BackdropTemplate")
  f:SetSize(width, height)
  Nock.UI.ApplyBackdrop(f)
  if styleKey then Nock.UI.RegisterBarBackdrop(f, styleKey) end

  local fill = f:CreateTexture(nil, "ARTWORK")
  fill:SetTexture(Nock.UI.GetBarTextureFor(textureKey))
  fill:SetPoint("TOPLEFT", 1, -1)
  fill:SetPoint("BOTTOMLEFT", 1, 1)
  fill:SetVertexColor(unpack(fillColor or C.COLORS.CAST_BAR))
  fill:SetWidth(math.max(1, width - 2))
  f.fill = fill
  f.maxWidth = width - 2
  Nock.UI.RegisterBarFill(fill, textureKey)

  local text = f:CreateFontString(nil, "OVERLAY")
  text:SetFont(Nock.UI.GetFont(), C.FONT.SIZE_OVERLAY, "OUTLINE")
  text:SetPoint("CENTER")
  text:SetTextColor(unpack(C.COLORS.TEXT))
  f.text = text
  Nock.UI.RegisterFontString(text, "SIZE_OVERLAY", "OUTLINE")

  return f
end

function Nock.UI.SetBarFill(bar, progress01)
  local p = math.max(0, math.min(1, progress01 or 0))
  bar.fill:SetWidth(math.max(0.01, p * bar.maxWidth))
end

-- Anchor a bar's fill texture to the LEFT (default) or RIGHT edge. Right-anchored
-- bars grow/drain from the right instead of the left — used by the swing-bar
-- "inverse" direction modes. Width is still driven by SetBarFill; only the side
-- the fill hugs changes. Idempotent; callers cache to avoid per-tick re-anchoring.
function Nock.UI.SetBarFillReverse(bar, reverse)
  bar.fill:ClearAllPoints()
  if reverse then
    bar.fill:SetPoint("TOPRIGHT", -1, -1)
    bar.fill:SetPoint("BOTTOMRIGHT", -1, 1)
  else
    bar.fill:SetPoint("TOPLEFT", 1, -1)
    bar.fill:SetPoint("BOTTOMLEFT", 1, 1)
  end
end

-- `reactScoped` (optional) marks the slot's texts as React-scoped for the
-- font registry — pass true from React views (the CD grid) so reactFont, when
-- set, overrides the global fontFace there. See RegisterFontString.
function Nock.UI.CreateIconSlot(parent, name, size, reactScoped)
  local f = CreateFrame("Frame", name, parent, "BackdropTemplate")
  f:SetSize(size, size)
  -- ApplyIconBorder (called at end) sets the backdrop AND positions the icon
  -- based on the active iconBorder/iconBorderSize profile values.

  local glow = CreateFrame("Frame", nil, f, "BackdropTemplate")
  glow:SetPoint("TOPLEFT", f, "TOPLEFT", -3, 3)
  glow:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 3, -3)
  glow:SetBackdrop({
    bgFile   = SOLID_TEX,
    edgeFile = SOLID_TEX,
    edgeSize = 3,
    insets   = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  glow:SetBackdropColor(0, 0, 0, 0)
  glow:SetBackdropBorderColor(0, 0.9, 0.9, 1)
  glow:Hide()
  f.glow = glow

  local icon = f:CreateTexture(nil, "ARTWORK")
  -- Initial 2/-2 inset is a placeholder; ApplyIconBorder (called below) sets
  -- the final position based on the active border thickness.
  icon:SetPoint("TOPLEFT", 2, -2)
  icon:SetPoint("BOTTOMRIGHT", -2, 2)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
  f.icon = icon

  -- Radial cooldown swipe over the icon. Idle until SetCooldown(start, dur) is
  -- called; Clear() to stop. Inherited APIs (SetHideCountdownNumbers, etc.) are
  -- 7.x+ so safe on Anniversary TBC.
  local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
  cd:SetAllPoints(icon)
  if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
  if cd.SetDrawSwipe           then cd:SetDrawSwipe(true)           end
  if cd.SetDrawEdge            then cd:SetDrawEdge(false)           end
  if cd.SetSwipeColor          then cd:SetSwipeColor(0, 0, 0, 0.75) end
  -- Hide any FontString child the template may have created so Blizzard's
  -- built-in countdown can't bleed through if SetHideCountdownNumbers above
  -- was a no-op on this client. (External addons like OmniCC create their own
  -- FontStrings as siblings, so this doesn't affect them.)
  for _, region in ipairs({ cd:GetRegions() }) do
    if region and region.GetObjectType and region:GetObjectType() == "FontString" then
      region:SetAlpha(0)
      region:Hide()
    end
  end
  -- noCooldownCount is set per-slot by the consumer (Frame_Cooldowns) once
  -- it has decided whether an external CD-text addon is installed.
  f.cooldown = cd

  -- Text-layer child frame, sits one level above the cooldown so the swipe
  -- never paints over the time/count numbers.
  local textLayer = CreateFrame("Frame", nil, f)
  textLayer:SetAllPoints(f)
  textLayer:SetFrameLevel(cd:GetFrameLevel() + 1)

  local cdText = textLayer:CreateFontString(nil, "OVERLAY")
  cdText:SetFont(Nock.UI.GetFont(), C.FONT.SIZE_OVERLAY, "OUTLINE")
  cdText:SetPoint("CENTER")
  cdText:SetTextColor(unpack(C.COLORS.TEXT))
  f.cdText = cdText
  Nock.UI.RegisterFontString(cdText, "SIZE_OVERLAY", "OUTLINE", reactScoped)

  -- Bottom-right stack count (item charge counts etc.). Empty by default.
  local countText = textLayer:CreateFontString(nil, "OVERLAY")
  countText:SetFont(Nock.UI.GetFont(), C.FONT.SIZE_OVERLAY, "OUTLINE")
  countText:SetPoint("BOTTOMRIGHT", -2, 2)
  countText:SetTextColor(unpack(C.COLORS.TEXT))
  f.countText = countText
  Nock.UI.RegisterFontString(countText, "SIZE_OVERLAY", "OUTLINE", reactScoped)

  -- Top-left badge (e.g. Drums "players in range"). Empty by default; only
  -- the Drums cooldown slot populates it.
  local topText = textLayer:CreateFontString(nil, "OVERLAY")
  topText:SetFont(Nock.UI.GetFont(), C.FONT.SIZE_OVERLAY, "OUTLINE")
  topText:SetPoint("TOPLEFT", 2, -2)
  topText:SetTextColor(unpack(C.COLORS.TEXT))
  f.topText = topText
  Nock.UI.RegisterFontString(topText, "SIZE_OVERLAY", "OUTLINE", reactScoped)

  -- Register for live border-refresh and apply the current border style.
  iconSlots[#iconSlots + 1] = f
  Nock.UI.ApplyIconBorder(f)

  return f
end

-- Mana-bar center text, shared by the classic mana bar (manaBarText) and the
-- React mana bar (reactManaText). Pure — LuaJIT-tested in
-- Tests/mana_format_test.lua. Callers diff on the integer inputs + mode so
-- the format only runs when the displayed value changes (perf rule).
function Nock.UI.FormatManaText(mode, cur, max, pct)
  if mode == "none"  then return "" end
  if mode == "value" then return string.format("%d", cur) end
  if mode == "both"  then return string.format("%d / %d", cur, max) end
  return string.format("%d%%", pct)   -- "percent" (default)
end

-- Severity colour for the Auto Shot delay readout, mirroring the React WA's
-- thresholds (seconds): >=0.50 red, >=0.25 orange, >=0.10 yellow, else green.
-- Shared by the classic swing row and the React cluster.
function Nock.UI.DelaySeverityColor(sec)
  if sec >= 0.50 then return 0.769, 0.118, 0.227 end
  if sec >= 0.25 then return 1.000, 0.702, 0.000 end
  if sec >= 0.10 then return 1.000, 0.957, 0.408 end
  return 0.000, 1.000, 0.596
end

function Nock.UI.SetIconHighlight(slot, color)
  if color then
    slot.glow:SetBackdropBorderColor(unpack(color))
    slot.glow:Show()
  else
    slot.glow:Hide()
  end
end

function Nock.UI.SetGlowBorderSize(slot, size)
  if not slot.glow then return end
  slot.glow:ClearAllPoints()
  slot.glow:SetPoint("TOPLEFT", slot, "TOPLEFT", -size, size)
  slot.glow:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", size, -size)
  slot.glow:SetBackdrop({
    bgFile   = SOLID_TEX,
    edgeFile = SOLID_TEX,
    edgeSize = size,
    insets   = { left = size, right = size, top = size, bottom = size },
  })
  slot.glow:SetBackdropColor(0, 0, 0, 0)
  -- Caller must re-apply border color via SetIconHighlight after this.
end

local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)

-- LibCustomGlow keeps its frame pools in file-local upvalues, so when a *newer*
-- MINOR of the library loads mid-session — BigWigs_Plugins is LoadOnDemand and
-- bundles a higher one than most addons ship — its file re-runs, rebinds
-- PixelGlow_Start/Stop to brand-new pools, and every glow frame we already
-- started still belongs to the retired pool. The library's Stop then hands a
-- foreign frame to the new pool, Blizzard's ObjectPoolMixin:Release rejects it
-- ("Attempted to release object ... that doesn't belong to this pool"), and
-- because the reject path skips the pool's resetter the `_PixelGlow<key>` field
-- is never cleared off our icon — so the central tick replays the same error on
-- every frame, thousands of times, and the orphaned ring keeps animating.
--
-- Detach such orphans ourselves before asking the library to touch them. Field
-- names are exactly what LibCustomGlow's addFrameAndTex stores: glowName .. key.
local GLOW_FIELDS = {
  { field = "_PixelGlowNockNext",      pool = "GlowFramePool"  },
  { field = "_AutoCastGlowNockNextAC", pool = "GlowFramePool"  },
  { field = "_ButtonGlow",             pool = "ButtonGlowPool" },
}

-- Diagnostic counter; inspect in-game with
--   /run print(Nock.UI.glowOrphansDropped)
Nock.UI.glowOrphansDropped = 0

local function poolOwns(pool, frame)
  if pool.IsActive then return pool:IsActive(frame) end
  if pool.activeObjects then return pool.activeObjects[frame] ~= nil end
  return true -- unrecognised pool shape: leave the decision to the library
end

local function dropOrphanedGlows(slot)
  if not LCG then return end
  for i = 1, #GLOW_FIELDS do
    local entry = GLOW_FIELDS[i]
    local f = slot[entry.field]
    if f then
      local pool = LCG[entry.pool]
      if pool and not poolOwns(pool, f) then
        slot[entry.field] = nil
        f:SetScript("OnUpdate", nil)
        f:Hide()
        f:ClearAllPoints()
        Nock.UI.glowOrphansDropped = Nock.UI.glowOrphansDropped + 1
      end
    end
  end
end

function Nock.UI.SetIconAlertGlow(slot, on, color)
  if not LCG then return end
  dropOrphanedGlows(slot)
  if on then
    LCG.ButtonGlow_Start(slot, color, 0.3)
  else
    LCG.ButtonGlow_Stop(slot)
  end
end

-- Profile-driven "next action" highlight. Each call stops *all* previously
-- started effects on the slot before optionally starting the configured one,
-- so changing the rotNextEffect setting cleanly hands off without leaving the
-- old glow running.
local function stopAllNextHighlights(slot)
  Nock.UI.SetIconHighlight(slot, nil)
  if not LCG then return end
  dropOrphanedGlows(slot)
  if LCG.PixelGlow_Stop     then LCG.PixelGlow_Stop(slot, "NockNext")        end
  if LCG.ButtonGlow_Stop    then LCG.ButtonGlow_Stop(slot)                   end
  if LCG.AutoCastGlow_Stop  then LCG.AutoCastGlow_Stop(slot, "NockNextAC")   end
end

-- Compact signature of a color for change-detection. Handles the {r,g,b,a}
-- array form (what everything here uses) and nil.
local function colorSig(c)
  if type(c) ~= "table" then return "-" end
  return string.format("%.3f/%.3f/%.3f/%.3f", c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1)
end

-- thicknessOverride (optional): pixel-ring line thickness. Defaults to 2;
-- the buff tracker passes 1 for a finer line since its icons are small.
--
-- Idempotent: most callers guard their on=true calls behind their own state
-- diff, but several off-paths don't — e.g. TotemTracker calls this with
-- on=false on three slots EVERY tick whenever the totem panel is hidden (which,
-- for a non-shaman, is always). Each such call used to run the full
-- stopAllNextHighlights → three LibCustomGlow *_Stop* calls, 30×/sec × 3 slots
-- for nothing. That churn is also what turned a single post-BigWigs-load pool
-- mismatch into thousands of "release object that doesn't belong to this pool"
-- errors. We stash the applied signature on the slot and no-op when the request
-- hasn't changed, matching the "frames early-exit when data is unchanged" rule.
function Nock.UI.SetIconNextHighlight(slot, on, colorOverride, thicknessOverride)
  -- Resolve the target parameters first so the signature reflects exactly what
  -- we'd draw (effect + color + thickness), then compare against last applied.
  local effect, color, thickness
  if on then
    effect = profile("rotNextEffect", "pixelGlow")
    if effect == "none" then on = false end
  end
  if on then
    color = colorOverride or profile("rotNextColor", nil) or C.COLORS.NEXT_HIGHLIGHT
    thickness = thicknessOverride or 2
  end

  local sig = on
    and (tostring(effect) .. "|" .. colorSig(color) .. "|" .. tostring(thickness))
    or "off"
  if slot._nockNextSig == sig then return end
  slot._nockNextSig = sig

  stopAllNextHighlights(slot)
  if not on then return end

  if effect == "static" or not LCG then
    Nock.UI.SetIconHighlight(slot, color)
    return
  end

  if effect == "pixelGlow" and LCG.PixelGlow_Start then
    LCG.PixelGlow_Start(slot, color, 10, 0.25, nil, thickness, nil, nil, true, "NockNext")
  elseif effect == "buttonGlow" and LCG.ButtonGlow_Start then
    LCG.ButtonGlow_Start(slot, color, 0.3)
  elseif effect == "autoCastGlow" and LCG.AutoCastGlow_Start then
    -- Signature is (r, color, N, frequency, scale, xOffset, yOffset, key) — the
    -- key is the 8th arg, NOT the 9th (that's frameLevel, and a string there
    -- blows up on GetFrameLevel()+key). One nil too many here also meant the
    -- glow landed on `_AutoCastGlow` while our Stop looked for the keyed field,
    -- so it could never be switched off.
    LCG.AutoCastGlow_Start(slot, color, nil, nil, nil, nil, nil, "NockNextAC")
  else
    -- Fallback if the chosen LCG entrypoint isn't present on this client.
    Nock.UI.SetIconHighlight(slot, color)
  end
end

function Nock.UI.CreateZoneSquare(parent, name, width, height)
  local f = CreateFrame("Frame", name, parent, "BackdropTemplate")
  f:SetSize(width, height)
  Nock.UI.ApplyBackdrop(f, C.COLORS.ZONE_INACTIVE_BG, C.COLORS.ZONE_INACTIVE_BORDER)

  local label = f:CreateFontString(nil, "OVERLAY")
  label:SetFont(Nock.UI.GetFont(), C.FONT.SIZE_OVERLAY, "OUTLINE")
  label:SetPoint("CENTER")
  label:SetTextColor(unpack(C.COLORS.TEXT))
  f.label = label
  Nock.UI.RegisterFontString(label, "SIZE_OVERLAY", "OUTLINE")

  return f
end

function Nock.UI.SetZoneActive(square, active)
  local C2 = Nock.Constants.COLORS
  if active then
    square:SetBackdropColor(unpack(C2.ZONE_ACTIVE_BG))
    square:SetBackdropBorderColor(unpack(C2.ZONE_ACTIVE_BORDER))
  else
    square:SetBackdropColor(unpack(C2.ZONE_INACTIVE_BG))
    square:SetBackdropBorderColor(unpack(C2.ZONE_INACTIVE_BORDER))
  end
end

-- Countdown encoding shared by the React buff row (UI/Frame_ReactBuffs.lua) and
-- the React corner icons (UI/Frame_ReactCorners.lua). Returns a diff key, the
-- rendered string, and whether it sits in the expiring-red band — so callers
-- can skip both the string build and the color call when nothing changed.
--
--   tval  0 = no text (steady aura), negative = whole minutes, positive = seconds
--
-- This lives here rather than in either view because two copies of it drifted
-- once already in this codebase's history for the clip threshold.
local REACT_LOW_SEC = 3

function Nock.UI.ReactCountdown(exp, dur, now)
  exp = exp or 0
  dur = dur or 0
  local rem = exp - now
  if rem < 0 then rem = 0 end

  local tval
  if exp <= 0 or dur <= 0 or rem <= 0 then
    tval = 0
  elseif rem >= 90 then
    tval = -math.ceil(rem / 60)
  else
    tval = math.ceil(rem)
  end

  if tval == 0 then
    return 0, "", false
  elseif tval < 0 then
    return tval, string.format("%dm", -tval), false
  end
  return tval, tostring(tval), tval <= REACT_LOW_SEC
end

-- React icon box: 1px black border, dark fill, cropped icon, a centered
-- countdown and a bottom state label. Never registered with RegisterBarFill /
-- RegisterFontString — React media is its own channel: SetReactSlotSize
-- resolves reactFont directly ("" = the reference C.FONT.PATH) and every
-- caller re-runs it on NOCK_VISUALS_CHANGED.
--
-- Font sizes are derived from the box edge against the reference 26px slot
-- (9px countdown, 7px label) so a resized corner icon stays in proportion and
-- the 26px buff row renders exactly as before.
local REACT_SLOT_BG   = { 0.08, 0.08, 0.08, 0.90 }
local REACT_SLOT_TEXT = { 1.00, 1.00, 1.00, 1.00 }
local REACT_SLOT_LOW  = { 0.77, 0.12, 0.23, 1.00 }
local REACT_SLOT_REF  = 26

local function reactSlotFonts(size)
  local time  = math.max(7, math.floor(size * 9 / REACT_SLOT_REF + 0.5))
  local label = math.max(6, math.floor(size * 7 / REACT_SLOT_REF + 0.5))
  return time, label
end

function Nock.UI.SetReactSlotSize(slot, size)
  slot:SetSize(size, size)
  local timeSize, labelSize = reactSlotFonts(size)
  -- reactFont/reactFontSize overrides ("" / 9 = the reference look). Every
  -- SetReactSlotSize caller re-runs on NOCK_VISUALS_CHANGED, so a change
  -- applies live.
  local font = Nock.UI.GetReactFont() or C.FONT.PATH
  local d = Nock.UI.GetReactFontDelta()
  safeSetFont(slot.time,  font, math.max(6, timeSize + d),  "OUTLINE")
  safeSetFont(slot.label, font, math.max(6, labelSize + d), "OUTLINE")
end

function Nock.UI.CreateReactSlot(parent, name, size)
  local slot = CreateFrame("Frame", name, parent, "BackdropTemplate")
  slot:SetBackdrop({
    bgFile   = SOLID_TEX,
    edgeFile = SOLID_TEX,
    edgeSize = 1,
    insets   = { left = 1, right = 1, top = 1, bottom = 1 },
  })
  slot:SetBackdropColor(unpack(REACT_SLOT_BG))
  slot:SetBackdropBorderColor(0, 0, 0, 1)

  local icon = slot:CreateTexture(nil, "ARTWORK")
  icon:SetPoint("TOPLEFT",     slot, "TOPLEFT",      1, -1)
  icon:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -1,  1)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  slot.icon = icon

  -- Countdown (center) and state label (bottom) are separate FontStrings so
  -- neither ever needs a SetFont call at repaint time.
  local time = slot:CreateFontString(nil, "OVERLAY")
  time:SetPoint("CENTER", slot, "CENTER", 0, 0)
  time:SetTextColor(unpack(REACT_SLOT_TEXT))
  slot.time = time

  local label = slot:CreateFontString(nil, "OVERLAY")
  label:SetPoint("BOTTOM", slot, "BOTTOM", 0, 2)
  slot.label = label

  Nock.UI.SetReactSlotSize(slot, size)
  slot:Hide()
  return slot
end

-- Repaint one slot from `item` = { icon, exp, dur, label, sub, desat }. Every
-- mutation sits behind a diff so the 10 Hz lane costs nothing when idle.
-- A non-nil `item.label` puts the slot in label mode (state text, no
-- countdown); otherwise it renders the ReactCountdown text.
--
-- `sub` is the additive form of the same bottom line: it rides ALONGSIDE the
-- countdown instead of replacing it. Label mode ignores it -- the two would be
-- competing for one FontString, and `label` is the mode that asked for it.
function Nock.UI.PaintReactSlot(slot, item, now)
  if item.icon ~= slot._icon then
    slot.icon:SetTexture(item.icon)
    slot._icon = item.icon
  end
  local desat = item.desat and true or false
  if desat ~= slot._desat then
    slot.icon:SetDesaturated(desat)
    slot._desat = desat
  end

  if item.label then
    if slot._mode ~= "l" then
      slot.time:SetText("")
      slot._tval, slot._low, slot._mode = nil, nil, "l"
      -- _label is dropped too: it may hold a `sub` caption from the other mode,
      -- which would make an identical label diff equal and skip its colouring.
      slot._label = nil
    end
    if item.label ~= slot._label then
      slot.label:SetText(item.label)
      -- MISSING is the actionable nag (nothing down at all) — red; RANGE is
      -- positional info — plain white.
      if item.label == "MISSING" then
        slot.label:SetTextColor(unpack(REACT_SLOT_LOW))
      else
        slot.label:SetTextColor(unpack(REACT_SLOT_TEXT))
      end
      slot._label = item.label
    end
    return
  end

  if slot._mode ~= "t" then
    slot.label:SetText("")
    slot._label, slot._mode = nil, "t"
    slot.label:SetTextColor(unpack(REACT_SLOT_TEXT))
  end

  -- "" rather than nil as the empty value: _label starts nil after a mode flip,
  -- so a nil `sub` still has to clear the string exactly once and then diff
  -- equal forever after.
  local sub = item.sub or ""
  if sub ~= slot._label then
    slot.label:SetText(sub)
    slot._label = sub
  end

  local tval, text, low = Nock.UI.ReactCountdown(item.exp, item.dur, now)
  if tval ~= slot._tval then
    slot.time:SetText(text)
    slot._tval = tval
  end
  if low ~= slot._low then
    slot._low = low
    if low then
      slot.time:SetTextColor(unpack(REACT_SLOT_LOW))
    else
      slot.time:SetTextColor(unpack(REACT_SLOT_TEXT))
    end
  end
end

-- The React cluster's built-in top-to-bottom bar order, and the sanitizer for
-- the user override (profile.reactBarOrder, mutated by Up/Down executes on the
-- React HUD tab). Anything that isn't a table means "built-in"; a table is
-- deduped, stripped of unknown keys, and topped up with whatever it's missing,
-- so every bar always places exactly once no matter what the profile holds.
-- Pure — LuaJIT-tested in Tests/react_order_test.lua. Callers must treat the
-- result as read-only: the fallback IS the shared built-in table.
local REACT_BAR_ORDER = { "auto", "melee", "range", "mana" }
local REACT_BAR_SET = {}
for i = 1, #REACT_BAR_ORDER do REACT_BAR_SET[REACT_BAR_ORDER[i]] = true end

function Nock.UI.ResolveReactBarOrder(stored)
  if type(stored) ~= "table" then return REACT_BAR_ORDER end
  local out, seen = {}, {}
  for i = 1, #stored do
    local k = stored[i]
    if REACT_BAR_SET[k] and not seen[k] then
      seen[k] = true
      out[#out + 1] = k
    end
  end
  for i = 1, #REACT_BAR_ORDER do
    local k = REACT_BAR_ORDER[i]
    if not seen[k] then out[#out + 1] = k end
  end
  return out
end

-- ---------------------------------------------------------------------------
-- React auto-bar axis projection. ONE definition of "a fraction of the cycle,
-- as a point on the bar" -- the clip/wind-up marks, the eWS brackets and the
-- GCD divider all place through this. The clip-threshold lesson is
-- that this arithmetic drifts the moment it exists in two places.
--
-- Returns (edge, x, mirrored): anchor the texture's CENTER to `edge` of the bar
-- at offset `x`. When `mirrored` (converge only) the caller places a SECOND
-- texture at "RIGHT" with -x; otherwise the second texture is hidden.
--
-- converge measures each of the mirrored pair across the HALF width; the
-- directional modes measure a single mark across the FULL inner width from the
-- fill's own origin edge. The 1px inset matches the fills, which start 1px in
-- from the border.
-- ---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- Device-pixel helpers. A "pixel" in SetWidth/SetPoint is a LOGICAL unit that
-- the UI scale multiplies into real screen pixels, and the two are wildly
-- different in practice: at a UI scale of 0.5333 (1440p on the 768-line
-- default) a 2-logical-px tick is 1.07 device px and a 1-logical-px one is
-- sub-pixel. That is why every mark on the auto bar rendered as a dim hairline
-- regardless of the width it was given.
--
-- So mark widths are specified in DEVICE pixels and converted here, and mark
-- positions are snapped so the quad's edges land on device boundaries instead
-- of straddling two columns at half brightness.
-- ---------------------------------------------------------------------------

-- Effective scale of `frame`, guarded for the pre-layout / headless cases.
-- Returns nil when there is nothing sensible to scale by, which every consumer
-- below treats as "no conversion".
function Nock.UI.PixelScale(frame)
  if not (frame and frame.GetEffectiveScale) then return nil end
  local s = frame:GetEffectiveScale()
  if type(s) ~= "number" or s <= 0 then return nil end
  return s
end

-- Logical width that renders as exactly `nDevice` real screen pixels.
function Nock.UI.DeviceWidth(nDevice, scale)
  local n = tonumber(nDevice) or 1
  if n <= 0 then n = 1 end
  local s = tonumber(scale)
  if not s or s <= 0 then return n end
  return n / s
end

-- Snap a CENTER coordinate so an `nDevice`-wide quad centred on it covers whole
-- device pixels. An even width wants its centre on a device boundary; an odd
-- width wants it on a half-pixel -- otherwise a 1px line is split across two
-- columns at half brightness each, which is exactly the "it looks 1px, then it
-- doesn't" flicker. Never moves a mark by as much as a device pixel, so the
-- threshold it marks stays where the maths put it.
function Nock.UI.PixelSnapCenter(x, scale, nDevice)
  local v = tonumber(x) or 0
  local s = tonumber(scale)
  if not s or s <= 0 then return v end
  local n = tonumber(nDevice) or 1
  local half = (n % 2 == 0) and 0 or 0.5
  local d = v * s
  d = math.floor(d - half + 0.5) + half
  return d / s
end

-- `scale` and `nDevice` are optional: pass both to have the result snapped to
-- the device-pixel grid (see Nock.UI.PixelSnapCenter). Omitted, the projection
-- is returned raw, which is what the pure-geometry tests assert.
function Nock.UI.ReactAxisPoint(frac, dir, halfW, innerW, scale, nDevice)
  frac = tonumber(frac) or 0
  if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
  local snap = Nock.UI.PixelSnapCenter
  if dir == "ltr" then
    return "LEFT", snap(1 + frac * (innerW or 0), scale, nDevice), false
  elseif dir == "rtl" then
    -- Snap the DISTANCE from the right edge, then re-negate: snapping the
    -- negative directly would round the wrong way for odd widths.
    return "RIGHT", -snap(1 + frac * (innerW or 0), scale, nDevice), false
  end
  -- converge (the reference look) and any unrecognised value.
  return "LEFT", snap(1 + frac * (halfW or 0), scale, nDevice), true
end

-- GCD progress for the divider, on the same 0-at-the-start / 1-at-the-end
-- convention the gold fill uses -- so the divider leaves the outer edge on the
-- press and closes on the centre as the GCD burns down.
--
-- nil means "draw nothing", and every non-running case must reach it: Core
-- zeroes state.gcd whenever the Steady probe isn't a GCD reading, and a zero
-- duration would otherwise divide to inf and park a line on the bar forever.
-- `remaining` is GetTime() against a server timestamp, so it is clamped both
-- ways rather than trusted.
function Nock.UI.ReactGcdFrac(gcd)
  if type(gcd) ~= "table" or not gcd.active then return nil end
  local dur = tonumber(gcd.duration)
  if not dur or dur <= 0 then return nil end
  local f = 1 - (tonumber(gcd.remaining) or 0) / dur
  if f < 0 then return 0 elseif f > 1 then return 1 end
  return f
end

-- ---------------------------------------------------------------------------
-- Free-placement wiring for the glued side panels (totem / pet status / repair).
-- One implementation so the three panels can't drift (the clip-threshold
-- lesson). The panel is almost fully covered by content (clickable slots on the
-- totem tracker), so dragging is handled by an overlay shown only while editing
-- that sits ABOVE the content and catches the drag — content clicks stay usable
-- when not editing. Saves to elementPositions[key] like the HUD rows.
-- ---------------------------------------------------------------------------

-- One-time wiring: overlay drag frame + nudge-pad registration. `applyGlue`
-- owns re-anchoring the panel to its welded spot (ClearAllPoints included).
function Nock.UI.EnsureFreePanel(panel, key, label, applyGlue)
  if panel._editBG then return end
  panel:SetMovable(true)
  panel:SetClampedToScreen(true)
  local bg = CreateFrame("Frame", nil, panel, "BackdropTemplate")
  bg:SetAllPoints(panel)
  bg:SetFrameLevel(panel:GetFrameLevel() + 10)  -- above the content so it catches drags
  Nock.UI.ApplyBackdrop(bg)
  bg:SetBackdropColor(0, 0, 0, 0.25)
  bg:SetBackdropBorderColor(unpack(C.COLORS.BORDER_UNLOCK))
  bg:EnableMouse(true)
  bg:RegisterForDrag("LeftButton")
  bg:SetScript("OnDragStart", function() panel:StartMoving(); panel._nockDragging = true end)
  bg:SetScript("OnDragStop", function()
    panel:StopMovingOrSizing()
    panel._nockDragging = false
    local pt, _, relPt, x, y = panel:GetPoint()
    local p = Nock.db.profile
    p.elementPositions = p.elementPositions or {}
    p.elementPositions[key] = { point = pt, relPoint = relPt, x = x, y = y }
  end)
  bg:Hide()
  panel._editBG = bg

  Nock.UI.RegisterNudgeable(panel, {
    label   = label,
    -- Drags are caught by the bg overlay above the content, so the selection
    -- click never reaches the panel itself.
    clickTarget = bg,
    active  = function() return Nock.FreeLayoutActive() end,
    get     = function()
      local p = Nock.db.profile.elementPositions
      return p and p[key]
    end,
    set     = function(pos)
      local p = Nock.db.profile
      p.elementPositions = p.elementPositions or {}
      p.elementPositions[key] = pos
      panel:ClearAllPoints()
      panel:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    end,
    -- Clearing the entry IS the reset: the next ApplyFreePanelPosition tick
    -- re-glues and re-captures, which is the only default the panel has.
    default = function()
      local p = Nock.db.profile
      if p.elementPositions then p.elementPositions[key] = nil end
      return nil
    end,
  })
end

-- Per-tick position pass (call from the panel's Refresh, before visibility
-- gates so leaving free mode re-glues even a hidden panel). Free: saved spot,
-- with a first-run capture of the glued spot so the panel doesn't jump; the
-- re-apply every tick is skipped mid-drag so the panel isn't yanked back.
-- Grid: re-glue when the scale changed or free mode just ended.
function Nock.UI.ApplyFreePanelPosition(panel, key, applyGlue, scale)
  local free = Nock.FreeLayoutActive()
  local s = scale or 1.0
  if free then
    if s ~= panel._nockScale then panel:SetScale(s); panel._nockScale = s end
    panel._editBG:SetShown(not Nock.IsLocked())
    if not panel._nockDragging then
      local p = Nock.db.profile
      p.elementPositions = p.elementPositions or {}
      local pos = p.elementPositions[key]
      if pos then
        panel:ClearAllPoints()
        panel:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
      else
        applyGlue(panel, s)
        if panel:GetLeft() then
          p.elementPositions[key] =
            { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT",
              x = panel:GetLeft(), y = panel:GetBottom() }
        end
      end
    end
  else
    panel._editBG:Hide()
    if s ~= panel._nockScale or panel._nockWasFree then
      panel:SetScale(s)
      applyGlue(panel, s)
      panel._nockScale = s
    end
  end
  panel._nockWasFree = free
  return free
end

----------------------------------------------------------------------------
-- Practice lane icons. Shared by the practice timeline window and the live
-- conveyor strip: both draw the same lane symbols, and two private caches of
-- the same textures is one cache too many.
----------------------------------------------------------------------------

local PRACTICE_ICON = {}
local PRACTICE_SYM_SPELL = {
  a = C.SpellID.AUTO_SHOT, s = C.SpellID.STEADY_SHOT, m = C.SpellID.MULTI_SHOT,
  A = C.SpellID.ARCANE_SHOT, r = C.SpellID.RAPTOR_STRIKE, w = C.SpellID.ATTACK,
  KC = C.SpellID.KILL_COMMAND, RF = C.SpellID.RAPID_FIRE, QS = C.SpellID.QUICK_SHOTS,
  Lust = C.SpellID.BLOODLUST, Drums = C.SpellID.DRUMS_OF_BATTLE,
  -- DST and Pot are ITEMS (PRACTICE_SYM_ITEM): the trinket's and the potion's own icons.
}
local PRACTICE_SYM_ITEM = { DST = C.PRACTICE.DST_ITEM, Pot = C.PRACTICE.HASTE_POT_ITEM }

-- The localised spell name behind a practice symbol, for the sentences the
-- coach line writes ("Missed the Steady Shot..."). Cached like the icons, and
-- only when the client actually had a name to give: a spell the client has not
-- cached yet must be asked again, not written off for the session.
local PRACTICE_NAME = {}

function Nock.UI.PracticeNameFor(sym)
  if not sym then return nil end
  local n = PRACTICE_NAME[sym]
  if n then return n end
  local id = PRACTICE_SYM_SPELL[sym]
  if not id then return nil end
  if C_Spell and C_Spell.GetSpellInfo then
    local info = C_Spell.GetSpellInfo(id)
    if type(info) == "table" then n = info.name
    elseif type(info) == "string" then n = info end
  end
  if not n and GetSpellInfo then n = GetSpellInfo(id) end
  if n and n ~= "" then
    PRACTICE_NAME[sym] = n
    return n
  end
  return nil
end

local function practiceSpellIcon(id)
  if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id) end
  if GetSpellTexture then return GetSpellTexture(id) end
  return nil
end

local function practiceItemIcon(id)
  if not id then return nil end
  if GetItemIcon then
    local i = GetItemIcon(id)
    if i then return i end
  end
  if C_Item and C_Item.GetItemIconByID then
    local i = C_Item.GetItemIconByID(id)
    if i then return i end
  end
  return nil
end

-- Only a real texture is cached: an item whose name/icon the client had not
-- cached yet must be asked again on the next build, not written off for the
-- session.
function Nock.UI.PracticeIconFor(sym)
  if not sym then return nil end
  local t = PRACTICE_ICON[sym]
  if t then return t end
  if PRACTICE_SYM_ITEM[sym] then
    t = practiceItemIcon(PRACTICE_SYM_ITEM[sym])
  else
    local id = PRACTICE_SYM_SPELL[sym]
    t = id and practiceSpellIcon(id) or nil
  end
  if t then PRACTICE_ICON[sym] = t end
  return t
end
