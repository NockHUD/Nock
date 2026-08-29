-- Structural smoke test for Config/Options.lua: builds the real options table
-- with WoW/Ace stubbed out, then asserts the family tree + regrouping landed.
-- Run from the repo root: luajit <path>/smoke_options.lua

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
local dialogClosed = 0
libs["AceConfigDialog-3.0"] = { AddToBlizOptions = function() return {} end, Close = function() dialogClosed = dialogClosed + 1 end }
-- lsmWidget() resolves through the REAL Nock.UI.PreferredMediaWidget, so this
-- has to be a working-enough AceGUI for UI/AceGUI_LSMDropdown.lua to register
-- its widgets into. Stubbing the answer instead would let the preference order
-- drift from what ships without any test noticing.
libs["AceGUI-3.0"] = {
  WidgetRegistry = {},
  RegisterWidgetType = function(self, name, ctor) self.WidgetRegistry[name] = ctor end,
}
-- Non-nil so the widget file doesn't bail; List() drives lsmValues(), and an
-- empty media list leaves each values table holding only its sentinel rows.
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
  -- Any constants table the builder touches resolves to an empty table, so
  -- list iterations run zero times and ID lookups read nil (both tolerated).
  Constants = setmetatable({}, {
    __index = function(t, k)
      local v = {}
      rawset(t, k, v)
      return v
    end,
  }),
}
-- Real modules don't load in the harness; Warnings/Helpers get a minimal
-- Catalog stub so the per-warning injection actually runs and the picker
-- shape below is testable against the same builder the game uses.
local STUB_CATALOGS = {
  Warnings = { Catalog = {
    { key = "test1", name = "Test Warning", enabledKey = "warnTest1",
      category = "pet",
      description = "Stub warning.", logic = "Never (harness only)." },
    { key = "test2", name = "Uncategorized Warning", enabledKey = "warnTest2",
      description = "Stub warning without a category.", logic = "Never (harness only)." },
  } },
  Helpers = { Catalog = {
    { key = "htest1", name = "Test Helper", enabledKey = "helpTest1",
      description = "Stub helper.", logic = "Never (harness only)." },
  } },
}
function Nock:GetModule(name) return STUB_CATALOGS[name] end
function Nock:SendMessage() end
_G.NockStub = Nock

-- .toc order: Config/Options.lua (18) loads BEFORE UI/AceGUI_LSMDropdown.lua
-- (22). Mirrored here on purpose -- it proves lsmWidget()'s lazy resolution
-- still finds the widgets even though they register after the options file.
dofile("Config/Options.lua")
dofile("UI/AceGUI_LSMDropdown.lua")
Nock:RegisterOptions()

local root = registered.args

-- Family tree at the root
local expectedRoot = {
  general = true, hud = true, alerts = true, trackers = true,
  utilities = true, experimental = true, profiles = true,
}
for k in pairs(expectedRoot) do ok(root[k] ~= nil, "root has " .. k) end
for k in pairs(root) do ok(expectedRoot[k], "unexpected root key: " .. tostring(k)) end

-- Old flat tabs moved under their families
local function child(fam, key) return root[fam] and root[fam].args and root[fam].args[key] end
ok(child("hud", "classic") and child("hud", "react"), "hud family holds the two mode branches")
local CB = child("hud", "classic") and child("hud", "classic").args or {}
local function classicChild(key) return CB[key] end
for _, key in ipairs({ "layout", "rotation", "swingBars", "manaBar", "rangeFinder", "cooldownGrid", "castBar", "background" }) do
  ok(classicChild(key), "classic branch holds " .. key)
end
ok(child("hud", "classic").childGroups == "tree", "classic branch renders children as a tree")
-- Active badge: branch names are functions so the sidebar can mark the live mode.
ok(type(child("hud", "classic").name) == "function"
   and type(child("hud", "react").name) == "function",
   "both branch names are functions (active badge)")
Nock.db.profile.hudMode = "classic"
ok(child("hud", "classic").name():find("active", 1, true)
   and not child("hud", "react").name():find("active", 1, true),
   "classic mode badges the classic branch only")
Nock.db.profile.hudMode = "react"
ok(child("hud", "react").name():find("active", 1, true)
   and not child("hud", "classic").name():find("active", 1, true),
   "react mode badges the react branch only")
Nock.db.profile.hudMode = nil
ok(classicChild("rotation") and classicChild("rotation").name == "Shot Bars",
   "rotation group renamed to Shot Bars")
-- The branch node itself is a landing page, not a blank: intro + look picker
-- (parity with the React landing).
ok(CB.intro and CB.intro.type == "description", "classic landing has an intro line")
ok(CB.hudMode and CB.hudMode.type == "select", "classic landing has the HUD look picker")
for _, key in ipairs({ "warnings", "helpers" }) do
  ok(child("alerts", key), "alerts family holds " .. key)
end
for _, key in ipairs({ "buffTracker", "debuffTracker", "totemTracker", "misdirect" }) do
  ok(child("trackers", key), "trackers family holds " .. key)
end
for _, key in ipairs({ "shopping", "mailbox", "weaveBind", "garment", "tonk", "practice" }) do
  ok(child("utilities", key), "utilities family holds " .. key)
end
for _, fam in ipairs({ "hud", "alerts", "trackers", "utilities" }) do
  ok(root[fam].childGroups == "tree", fam .. " renders children as a tree")
  ok(root[fam].args.intro, fam .. " has an intro line")
end

-- General regrouping: action buttons on the page, sections as sidebar children
local g = root.general.args
ok(root.general.childGroups == "tree", "general: sections are left-sidebar children")
ok(g.lockState and g.lockState.type == "description", "general: lock state line present")
ok(g.lockAll and g.lockAll.type == "execute", "general: Lock is its own button")
ok(g.unlockAll and g.unlockAll.type == "execute", "general: Unlock is its own button")
ok(g.lockAll.name == "Lock all frames" and g.unlockAll.name == "Unlock all frames",
   "general: static button labels (no layout shift)")
ok(type(g.lockAll.disabled) == "function" and type(g.unlockAll.disabled) == "function",
   "general: the already-active side greys out")
ok(g.lockAll.order < g.unlockAll.order and g.unlockAll.order < g.lockState.order,
   "general: buttons pinned up top, state line on its own row below them")
ok(g.locked == nil, "general: the old flipping button is gone")
ok(g.runWizard and g.runWizard.order > g.unlockAll.order, "general: run-wizard below the lock row")
ok(g.resetPos and g.resetPos.order > g.runWizard.order - 2, "general: reset position beside the wizard button")
ok(g.grpLook and g.grpLook.args.hudMode, "general: HUD look group holds hudMode")
ok(g.grpVisibility and g.grpVisibility.args.hideOoc, "general: visibility group holds hideOoc")
-- Background moved to the Classic branch (the backdrop box is classic-only:
-- React paints no box — HUD:ApplyBackground short-circuits in react mode).
ok(g.grpBackground == nil, "general: background group moved out")
local cbg = classicChild("background")
ok(cbg and not cbg.inline and cbg.args.backgroundEnabled and cbg.args.backgroundColor
   and cbg.args.backgroundOpacity, "classic background node holds the fill controls")
ok(cbg and cbg.args.hudBorder and cbg.args.hudBorderSize and cbg.args.hudBorderColor
   and cbg.args.hudBorderOpacity, "classic background node holds the border controls")
ok(cbg and cbg.args.backgroundReactNote, "classic background: classic-only pointer note present")
ok(g.grpCastBar and g.grpCastBar.args.showAutoShotCast, "general: cast bar group")
ok(g.grpMedia and g.grpMedia.args.barTexture, "general: media group")
for _, key in ipairs({ "grpLook", "grpVisibility", "grpCastBar", "grpMedia", "grpSetup" }) do
  ok(g[key] and not g[key].inline, "general: " .. key .. " is a sidebar child, not inline")
end
ok(g.grpSetup and g.grpSetup.args.setupCheckIntro, "general: setup-check tab holds the intro")
ok(g.setupCheckHeader == nil and g.setupCheckIntro == nil, "general: setup-check entries moved off the top level")
ok(g.reactHeader == nil and g.bgHeader == nil and g.mediaHeader == nil, "general: headers gone")
ok(g.hudMode == nil and g.opacity == nil, "general: no duplicates left at tab level")

-- Layout regrouping
local l = classicChild("layout").args
ok(l.grpPlacement and l.grpPlacement.args.freeLayout, "layout: placement group")
ok(l.grpElements and l.grpElements.args.showGcdBar, "layout: elements group holds showGcdBar")
ok(l.grpElements.args.showCastBar, "layout: one-liner toggles moved too")
ok(l.grpPanels and l.grpPanels.args.repairPanelToggle, "layout: panels group")
ok(l.grpScaling and l.grpScaling.args.totemScale, "layout: scaling group")
ok(l.rowsHeader == nil and l.panelsHeader == nil and l.scalingHeader == nil and l.alignHeader == nil,
   "layout: headers gone")

-- Rotation regrouping
local r = classicChild("rotation").args
ok(r.grpShotBars and r.grpShotBars.args.shotBarsColorSpark, "rotation: shot bars group")
ok(r.grpEngine and r.grpEngine.args.rotQuiverEquipped, "rotation: engine group")
ok(r.grpClipTicks and r.grpClipTicks.args.showWindupMark, "rotation: clip ticks group")
-- The safety margin and its three presets were retired in 1.0.19: the ticks are
-- cast + measured wind-up + latency, with nothing to hand-tune.
ok(r.grpClipTicks.args.clipSafetyMargin == nil and r.grpClipTicks.args.clipPresetTight == nil,
   "rotation: no clip safety margin left to set")
ok(r.grpNextHighlight and r.grpNextHighlight.args.rotNextColor, "rotation: highlight group")
ok(r.shotBarsHeader == nil and r.shotBarsFooter == nil, "rotation: headers gone")
ok(r.rotationLabelsGroup, "rotation: label rename group untouched")
-- The rename group is twelve text inputs of pure cosmetics and used to sort
-- ABOVE the functional sections, burying the shot-bar colours and clip settings
-- below a wall of boxes. Keep it last.
ok(r.rotationLabelsGroup.order > r.grpShotBars.order,
   "rotation: renames sort below the shot bars")
ok(r.rotationLabelsGroup.order > r.grpNextHighlight.order,
   "rotation: renames sort last of all the sections")
ok(r.grpShotBars.args.shotBarsColorQueue and r.grpShotBars.args.shotBarsColorQueueLive,
   "rotation: both queue-window colours are in the shot bars group")
-- The melee-lane height slider must be IN the regrouped list (Options.lua's
-- regroup drops anything not named there) and must sort under the bar height it
-- splits, not somewhere else in the pile.
ok(r.grpShotBars.args.shotBarsMeleeHeight
   and r.grpShotBars.args.shotBarsMeleeHeight.type == "range",
   "rotation: melee lane height slider is in the shot bars group")
ok(r.grpShotBars.args.shotBarsMeleeHeight.order > r.grpShotBars.args.shotBarsHeight.order
   and r.grpShotBars.args.shotBarsMeleeHeight.order < r.grpShotBars.args.shotBarsReverse.order,
   "rotation: melee lane height sits directly under the bar height")
-- The annotated bar diagram. dialogControl must name the widget registered by
-- UI/AceGUI_ShotBarsLegend.lua, or AceConfigDialog silently falls back to a
-- plain Label and the panel just shows nothing.
ok(r.grpShotBars.args.shotBarsLegend
   and r.grpShotBars.args.shotBarsLegend.dialogControl == "NockShotBarsLegend",
   "rotation: shot bars legend uses the custom widget")
ok(r.grpShotBars.args.shotBarsLegend.width == nil,
   "rotation: legend has no width key, so AceConfigDialog fills it")

-- React page: landing (intro + hudMode) plus six subtabs as tree children.
local ra = child("hud", "react").args
local raSize, raBars, raRange, raGrid, raBuff, raSkin =
  ra.tabSize and ra.tabSize.args or {}, ra.tabBars and ra.tabBars.args or {},
  ra.tabRange and ra.tabRange.args or {}, ra.tabGrid and ra.tabGrid.args or {},
  ra.tabBuff and ra.tabBuff.args or {}, ra.tabSkin and ra.tabSkin.args or {}
for _, k in ipairs({ "tabSize", "tabBars", "tabRange", "tabGrid", "tabBuff", "tabSkin" }) do
  ok(ra[k] and ra[k].type == "group" and not ra[k].inline, "react: subtab " .. k .. " present")
end
ok(child("hud", "react").childGroups == "tree", "react: subtabs render as tree children")

-- Same diagram for the React converge bar, under its own Auto Shot bar header.
ok(raBars.reactAutoLegend
   and raBars.reactAutoLegend.dialogControl == "NockReactBarLegend",
   "react: converge bar legend uses the custom widget")
ok(raBars.reactAutoLegend and raBars.reactAutoLegend.width == nil,
   "react: legend has no width key, so AceConfigDialog fills it")
ok(raBars.autoHeader and raBars.reactAutoLegend.order > raBars.autoHeader.order
   and raBars.reactAutoLegend.order < raBars.reactShowNotation.order,
   "react: legend sits between the Auto Shot bar header and its toggles")

-- React corner icons: two opt-in toggles in Elements, three geometry sliders
-- in Skin. The toggles must be opt-in shaped (default false reads as off), so
-- they cannot use the default-ON reactToggle helper.
ok(raSize.reactShowAspectIcon and raSize.reactShowAspectIcon.type == "toggle",
   "react: aspect corner icon toggle present")
ok(raSize.reactShowMarkIcon and raSize.reactShowMarkIcon.type == "toggle",
   "react: Hunter's Mark corner icon toggle present")
ok(raSize.reactShowAspectIcon.order > raSize.elementsHeader.order
   and raSize.reactShowMarkIcon.order < raSize.orderHeader.order,
   "react: corner toggles sit inside the Elements section")
ok(type(raSize.reactShowAspectIcon.disabled) == "function"
   and type(raSize.reactShowMarkIcon.disabled) == "function",
   "react: corner toggles grey out off React mode")

ok(raSkin.reactCornerIconSize and raSkin.reactCornerIconSize.type == "range"
   and raSkin.reactCornerIconSize.min == 20 and raSkin.reactCornerIconSize.max == 48,
   "react: corner size slider spans 20..48")
ok(raSkin.reactCornerIconX and raSkin.reactCornerIconX.max == 120
   and raSkin.reactCornerIconY and raSkin.reactCornerIconY.max == 120,
   "react: corner offset sliders span up to 120px")
ok(raSkin.reactCornerIconSize.order > raSkin.skinHeader.order
   and raSkin.reactCornerIconY.order < raSkin.reactColorAutoFill.order,
   "react: corner geometry sits in Skin, above the colour pickers")

-- The DO NOT RELEASE banner preview button: sits in the warnings tab's
-- Preview section beside the sample-squares button (the banner is not a
-- square, so the square demo can't show it).
local wa = child("alerts", "warnings").args
-- Warnings themed sub-pages: the landing page keeps only the master toggle +
-- intro; "Appearance & Preview" and the category nodes (You/Pet/Combat/
-- Gear & Binds/Boss, plus an "Other" fallback) are sidebar children, each
-- holding its warnings as the familiar inline boxes. Category comes from the
-- catalog entry; a missing/unknown category files under Other so a new
-- warning can never silently vanish.
local ws = wa.settings and wa.settings.args or {}
ok(wa.settings and wa.settings.type == "group" and not wa.settings.inline,
   "warnings: Appearance & Preview is a sidebar child, not page content")
ok(ws.warningIconSize and ws.warningLabelFont and ws.previewButton,
   "warnings: settings node holds the appearance + preview controls")
ok(ws.noReleasePreview and ws.noReleasePreview.type == "execute",
   "warnings: DO NOT RELEASE preview button present")
ok(ws.noReleasePreview and ws.previewButton
   and ws.noReleasePreview.order > ws.previewButton.order,
   "warnings: banner preview sits in the Preview section")
ok(child("alerts", "warnings").childGroups == "tree",
   "warnings: children render as sidebar sub-pages")
ok(wa.warningsHeader == nil and wa.warningsIntro == nil,
   "warnings: the old list header/intro are gone")
-- Stub catalog: test1 declares category="pet"; test2 has no category.
ok(wa.cat_pet and wa.cat_pet.type == "group" and not wa.cat_pet.inline
   and wa.cat_pet.name == "Pet",
   "warnings: declared category files under its themed node")
local wg = wa.cat_pet and wa.cat_pet.args.warning_test1
ok(wg and wg.inline == true and wg.name == "Test Warning",
   "warnings: warning renders as a flat inline box inside its category")
ok(wg and wg.args.enabled and wg.args.info, "warnings: box keeps the builder's controls")
ok(wa.cat_other and wa.cat_other.args.warning_test2,
   "warnings: category-less warning falls back to the Other node")
ok(wa.settings.order < wa.cat_pet.order and wa.cat_pet.order < wa.cat_other.order,
   "warnings: settings first, Other last")
local hg = child("alerts", "helpers").args.helper_htest1
ok(hg and hg.inline == true and hg.name == "Test Helper",
   "helpers: still flat inline boxes with a plain name")

-- Helpers overhaul: the expiring-warning threshold plus the layout knobs the
-- panel gained when it became a standard movable/styled floating panel.
local ha = child("alerts", "helpers").args
ok(ha.helpersExpiringThreshold and ha.helpersExpiringThreshold.type == "range"
   and ha.helpersExpiringThreshold.min == 0 and ha.helpersExpiringThreshold.max == 600,
   "helpers: expiring threshold slider 0..600")
ok(ha.helpersIconSize and ha.helpersIconSize.type == "range"
   and ha.helpersIconSize.min == 24 and ha.helpersIconSize.max == 64,
   "helpers: icon size slider 24..64")
ok(ha.helpersIconGap and ha.helpersIconGap.type == "range", "helpers: icon gap slider")
ok(ha.helpersScale and ha.helpersScale.type == "range"
   and ha.helpersScale.min == 0.5 and ha.helpersScale.max == 2.0,
   "helpers: scale slider 0.5..2.0")
ok(ha.helpersResetPos and ha.helpersResetPos.type == "execute",
   "helpers: position reset button")
-- Third-party WA author names belong only in the functional match STRING
-- (Config/Defaults.lua), never in prose the user reads.
ok(ha.helpersHideWA and not ha.helpersHideWA.desc:find("Fojji", 1, true),
   "helpers: WA auto-hide desc carries no third-party name")
ok(ha.intro and not ha.intro.name:find("32px", 1, true),
   "helpers: intro rewritten (no stale 32px copy)")

-- Experimental sub-pages: one sidebar child per experiment (the countdown
-- dial rides with the medallion — it's the same experiment). Landing page
-- keeps only the opt-in disclaimer.
local ex = root.experimental.args
ok(root.experimental.childGroups == "tree", "experimental: children are sidebar sub-pages")
ok(ex.grpMedallion and not ex.grpMedallion.inline
   and ex.grpMedallion.args.medallionEnabled and ex.grpMedallion.args.medallionRingColorHold,
   "experimental: medallion page holds the icon AND ring controls")
ok(ex.grpSapper and ex.grpSapper.args.mdSapperAnnounceScope,
   "experimental: sapper column page")
ok(ex.grpZoom and ex.grpZoom.args.rangeZoomLevel,
   "experimental: zoomed weave bar page")
-- Release bar (Aerthax retry grid): its own experiment page, all four knobs.
local rb = ex.grpRelease and ex.grpRelease.args or {}
ok(ex.grpRelease and not ex.grpRelease.inline,
   "experimental: release bar page present")
ok(rb.releaseBarEnabled and rb.releaseBarEnabled.type == "toggle",
   "experimental: release bar master toggle")
ok(rb.releaseBarHeight and rb.releaseBarHeight.type == "range",
   "experimental: release bar height slider")
ok(rb.releaseBarLabels and rb.releaseBarLabels.type == "toggle"
   and rb.releaseBarNotches and rb.releaseBarNotches.type == "toggle",
   "experimental: release bar readout + notch toggles")
ok(rb.releaseBarAlways and rb.releaseBarAlways.type == "toggle",
   "experimental: release bar always-visible toggle")
for _, k in ipairs({ "releaseBarAlways", "releaseBarHeight", "releaseBarLabels", "releaseBarNotches" }) do
  ok(rb[k] and type(rb[k].disabled) == "function",
     "experimental: " .. k .. " greys out while the bar is off")
end
ok(ex.v3Header == nil and ex.sapperHeader == nil and ex.zoomHeader == nil
   and ex.releaseHeader == nil,
   "experimental: section headers gone")

-- Range-bar center divider (the melee-boundary tick): width slider + colour
-- picker in Skin. The slider needs its own narrow span — the shared
-- skinRange helper starts at 8px, which for a 1px tick is nonsense.
ok(raSkin.reactRangeDividerWidth and raSkin.reactRangeDividerWidth.type == "range"
   and raSkin.reactRangeDividerWidth.min == 1 and raSkin.reactRangeDividerWidth.max == 8,
   "react: divider width slider spans 1..8")
ok(raSkin.reactColorRangeDivider and raSkin.reactColorRangeDivider.type == "color",
   "react: divider colour picker present")
ok(raSkin.reactRangeDividerWidth and raSkin.reactColorRangeDivider
   and raSkin.reactRangeDividerWidth.order > raSkin.skinHeader.order
   and raSkin.reactColorRangeDivider.order > raSkin.reactColorRangeResync.order
   and raSkin.reactColorRangeDivider.order < raSkin.resetSkin.order,
   "react: divider knobs sit in Skin, colour after the range colours")
ok(raSkin.reactRangeDividerWidth and raSkin.reactColorRangeDivider
   and type(raSkin.reactRangeDividerWidth.disabled) == "function"
   and type(raSkin.reactColorRangeDivider.disabled) == "function",
   "react: divider knobs grey out off React mode")
-- Reset must write the divider keys back too (SKIN_REFERENCE membership —
-- a key missing there reads nil after reset until /reload).
pcall(raSkin.resetSkin and raSkin.resetSkin.func or function() end)
ok(Nock.db.profile.reactRangeDividerWidth == 1,
   "react: reset restores divider width 1")
local dc = Nock.db.profile.reactColorRangeDivider
ok(type(dc) == "table" and dc[1] == 1 and dc[4] == 0.9,
   "react: reset restores divider colour (white @ 0.9)")

-- Weave Bind: the manual sits below the macro controls, and the coach's sound
-- pickers are hidden from the GUI without being deleted (the settings survive).
local wb = child("utilities", "weaveBind").args
ok(wb.howHeader and wb.howIntro
   and wb.howIntro.order > wb.weaveBindMacroUp.order
   and wb.howIntro.order > wb.weaveBindRestore.order,
   "weaveBind: 'How it works' sits below the macros and the restore button")
ok(wb.intro and wb.intro.order < wb.weaveBindEnabled.order
   and #wb.intro.name < 200,
   "weaveBind: only a short experimental flag stays above the controls")
for _, k in ipairs({ "coachHeader", "weaveCoachSoundsEnabled", "weaveCoachStruckSound",
                     "weaveCoachStruckPreview", "weaveCoachReleaseSound",
                     "weaveCoachReleasePreview" }) do
  ok(wb[k] and wb[k].hidden == true, "weaveBind: " .. k .. " kept but hidden")
end
-- The coach's own explanation documents live Range Finder bar stages, so it
-- must survive the section being hidden — it moved into "How it works".
ok(wb.coachIntro == nil and wb.howIntro.name:find("GO IN", 1, true),
   "weaveBind: coach cycle explanation folded into 'How it works'")

-- Press macro builder: the same four switches the wizard's extras page offers,
-- editing the same stored text. They sit ABOVE the macro boxes so the user sees
-- the text they just generated.
ok(wb.weaveSnowball and wb.weaveSnowball.type == "toggle", "builder: Snowball poke toggle")
ok(wb.weaveSnowballGate and wb.weaveSnowballGate.type == "toggle", "builder: garment gate toggle")
ok(wb.weaveGateGarment and wb.weaveGateGarment.type == "select", "builder: garment picker")
ok(wb.weaveGateDirection and wb.weaveGateDirection.type == "select", "builder: direction picker")
ok(wb.builderHeader and wb.builderHeader.order < wb.weaveSnowball.order,
   "builder: header above its controls")
for _, k in ipairs({ "builderHeader", "weaveSnowball", "weaveSnowballGate",
                     "weaveGateGarment", "weaveGateDirection" }) do
  ok(wb[k].order > wb.weaveBindKey.order and wb[k].order < wb.weaveBindMacroDown.order,
     "builder: " .. k .. " sits between the key and the macro boxes")
end
-- Both selects must normalise their item fonts or they inherit the LSM Font
-- dropdown's leaked typeface (shared AceGUI item pool).
ok(wb.weaveGateGarment.dialogControl == "Nock_LSM_Plain"
   and wb.weaveGateDirection.dialogControl == "Nock_LSM_Plain",
   "builder: both selects use the plain LSM widget")
-- Nothing in the builder is reachable while the feature is off, and the three
-- gate controls need a poke to gate.
for _, k in ipairs({ "weaveSnowball", "weaveSnowballGate", "weaveGateGarment", "weaveGateDirection" }) do
  ok(type(wb[k].disabled) == "function", "builder: " .. k .. " greys out")
end
ok(wb.weaveGateGarment.values and wb.weaveGateGarment.values.shirt and wb.weaveGateGarment.values.tabard,
   "builder: garment picker offers shirt and tabard")
ok(wb.weaveGateDirection.values and wb.weaveGateDirection.values.off and wb.weaveGateDirection.values.on,
   "builder: direction picker offers both directions")

-- Boss Garment content
local ga = child("utilities", "garment").args
ok(ga.weaveBindGarmentAutoFlip and ga.weaveBindGarmentAutoReequip, "garment: both toggles present")
ok(child("utilities", "weaveBind").args.garmentPointer, "weaveBind: pointer left behind")
ok(child("utilities", "weaveBind").args.weaveBindGarmentAutoFlip == nil, "weaveBind: toggle moved out")

-- hudMode mirror: one builder, three homes, same stored value.
ok(root.hud.args.hudMode and root.hud.args.hudMode.type == "select",
   "hud landing has the HUD look picker")
ok(g.grpLook.args.hudMode and ra.hudMode, "hudMode still on General and React")
pcall(root.hud.args.hudMode.set, nil, "react")
ok(g.grpLook.args.hudMode.get() == "react" and ra.hudMode.get() == "react",
   "hudMode set on the hud landing reads back through the other homes")
pcall(g.grpLook.args.hudMode.set, nil, "classic")
ok(root.hud.args.hudMode.get() == "classic", "and the reverse direction")

-- Weave engine mirror: inline box on both timing pages, one stored value.
local rEng = raBars.grpEngine
ok(rEng and rEng.inline and rEng.args and rEng.args.rotQuiverEquipped and rEng.args.rotWeaveProxMax,
   "react Bars: inline weave engine box with the four tunables")
ok(rEng and rEng.args.rotRaptorWeaveHeadroom.disabled == nil,
   "react weave engine is NOT react-gated (engine settings apply in both looks)")
if rEng then pcall(rEng.args.rotRaptorWeaveHeadroom.set, nil, 1.25) end
ok(r.grpEngine.args.rotRaptorWeaveHeadroom.get() == 1.25,
   "weave engine set through React reads back through Classic")

-- Cast bar mirror: Classic gets a node (reserved home for future styling);
-- React mirrors only the genuinely shared non-combat-casts toggle (its own
-- cast bar keys reactShowCastBar/reactShowAutoShotCast already sit in
-- Size & Elements).
local cCast = classicChild("castBar")
ok(cCast and cCast.args.showAutoShotCast and cCast.args.castBarNonCombatCasts,
   "classic branch has the Cast Bar node with both settings")
ok(raSize.castBarNonCombatCasts, "react Size & Elements mirrors non-combat casts")
ok(raSize.castBarNonCombatCasts
   and raSize.castBarNonCombatCasts.desc:find("same setting", 1, true),
   "react mirror desc names its canonical home")
if cCast then pcall(cCast.args.castBarNonCombatCasts.set, nil, true) end
ok(raSize.castBarNonCombatCasts and raSize.castBarNonCombatCasts.get() == true
   and g.grpCastBar.args.castBarNonCombatCasts.get() == true,
   "non-combat casts set through Classic reads back through React and General")

-- Hide-Blizzard toggle: shared behavior, so it must appear in BOTH mirrored
-- homes (General → Cast bar and Classic → Cast Bar) and write one key.
ok(cCast and cCast.args.hideBlizzardCastBar
   and cCast.args.hideBlizzardCastBar.type == "toggle",
   "classic cast bar: hide-Blizzard toggle present")
ok(g.grpCastBar.args.hideBlizzardCastBar
   and g.grpCastBar.args.hideBlizzardCastBar.type == "toggle",
   "general cast bar: hide-Blizzard toggle present")
if cCast and cCast.args.hideBlizzardCastBar then
  pcall(cCast.args.hideBlizzardCastBar.set, nil, true)
end
ok(g.grpCastBar.args.hideBlizzardCastBar
   and g.grpCastBar.args.hideBlizzardCastBar.get() == true,
   "hide-Blizzard set through Classic reads back through General")
Nock.db.profile.hideBlizzardCastBar = nil

-- Classic-only styling: lives beside the mirrored behavior on Classic → Cast
-- Bar and on Swing Bars. NOT mirrored — General's copy stays behavior-only
-- (React's cast bar styling is its Skin).
local cc = cCast and cCast.args or {}
ok(cc.castBarHeight and cc.castBarHeight.type == "range"
   and cc.castBarTexture and cc.castBarColor and cc.castBarColor.type == "color"
   and cc.castBarShowIcon,
   "classic cast bar: styling controls present")
ok(cc.stylingHeader and cc.castBarHeight.order > cc.castBarNonCombatCasts.order,
   "classic cast bar: styling sits below the mirrored behavior")
ok(g.grpCastBar.args.castBarColor == nil and g.grpCastBar.args.castBarHeight == nil,
   "general cast bar mirror stays behavior-only")
local sb = classicChild("swingBars") and classicChild("swingBars").args or {}
ok(sb.autoShotBarColor and sb.autoShotBarColor.type == "color"
   and sb.meleeBarColor and sb.meleeBarColor.type == "color",
   "swing bars: fill color pickers present")
ok(sb.clipTickSteadyColor and sb.clipTickMultiColor and sb.clipTickWindupColor,
   "swing bars: clip tick color pickers present")

-- Custom cooldown entries: one cooldownCustom store, editable from both grid
-- pages. (In this harness CDMOD is nil, so the classic ordered list stays
-- empty — assert the store and the React manage list instead.)
ok(raGrid.addBtn and raGrid.addId and raGrid.addType and raGrid.addProc and raGrid.addLabel,
   "react grid: custom add form present")
pcall(raGrid.addType and raGrid.addType.set or error, nil, "spell")
pcall(raGrid.addId and raGrid.addId.set or error, nil, "34074")
pcall(raGrid.addBtn and raGrid.addBtn.func or error)
local customs = Nock.db.profile.cooldownCustom
ok(type(customs) == "table" and #customs == 1 and customs[1].id == 34074
   and customs[1].type == "spell",
   "react add form writes the shared cooldownCustom store")
ok(raGrid.rcust_1 and raGrid.rcust_rm_1, "react grid: manage list shows the new entry")
pcall(raGrid.rcust_rm_1 and raGrid.rcust_rm_1.func or error)
ok(type(Nock.db.profile.cooldownCustom) == "table" and #Nock.db.profile.cooldownCustom == 0
   and raGrid.rcust_1 == nil,
   "react Remove empties the store and the list")

-- Tab-level whitelists: a future option added to a tidied tab's table literal
-- but not to the matching regroup list would silently stay ungrouped at the
-- top level (regroup's `if entry then` skips missing keys without complaint).
-- Fail loudly instead: every top-level key must be expected.
local function onlyKeys(args, allowed, label, prefixes)
  local set = {}
  for _, k in ipairs(allowed) do set[k] = true end
  for k in pairs(args) do
    local okKey = set[k]
    if not okKey and prefixes then
      for _, p in ipairs(prefixes) do
        if type(k) == "string" and k:sub(1, #p) == p then okKey = true break end
      end
    end
    ok(okKey, label .. ": unexpected top-level key '" .. tostring(k)
       .. "' — add it to a regroup/subtab list (or this whitelist)")
  end
end
onlyKeys(root.general.args,
  { "intro", "lockState", "lockAll", "unlockAll", "minimapIcon", "runWizard", "resetPos", "scale",
    "grpLook", "grpVisibility", "grpCastBar", "grpMedia", "grpSetup" },
  "general")
onlyKeys(root.hud.args, { "intro", "hudMode", "classic", "react" }, "hud family")
onlyKeys(root.experimental.args, { "intro", "grpMedallion", "grpSapper", "grpZoom", "grpRelease" }, "experimental")
onlyKeys(wa, { "masterToggle", "intro", "settings" }, "warnings", { "cat_" })
onlyKeys(wa.settings and wa.settings.args or {},
  { "appearanceHeader", "warningIconSize", "warningBorderSize", "warningLabelOffset",
    "warningLabelSize", "warningLabelFont", "warningLabelStyle", "warningLabelUpper",
    "previewHeader", "previewIntro", "previewButton", "noReleasePreview" },
  "warnings settings")
onlyKeys(classicChild("layout").args,
  { "grpPlacement", "grpElements", "grpPanels", "grpScaling" },
  "layout")
onlyKeys(classicChild("rotation").args,
  { "masterToggle", "intro", "rotationHelperEnabled", "rotationMode",
    "weaveNotationEnabled", "rotationLabelsGroup",
    "grpShotBars", "grpEngine", "grpClipTicks", "grpNextHighlight" },
  "rotation")

-- React subtab whitelists: the dynamic rebuilders write keys by prefix into
-- their OWN subtab table — a key surfacing anywhere else means a rebuilder
-- is still aiming at the react root (it would render on the landing page).
onlyKeys(ra, { "intro", "hudMode", "tabSize", "tabBars", "tabRange", "tabGrid", "tabBuff", "tabSkin" },
  "react root")
onlyKeys(raSize, { "sizeHeader", "reactWidth", "reactScale", "elementsHeader", "elementsNote",
  "reactShowAutoBar", "reactShowMeleeBar", "reactShowRangeBar", "reactShowManaBar", "reactManaText",
  "reactShowCastBar", "reactShowAutoShotCast", "reactShowGrid", "reactShowAspectIcon", "reactShowMarkIcon",
  "orderHeader", "order_reset", "castBarNonCombatCasts" }, "react tabSize",
  { "order_lbl_", "order_up_", "order_dn_" })
onlyKeys(raBars, { "autoHeader", "reactAutoLegend", "reactShowNotation", "reactShowDelay",
  "reactShowBrackets", "reactShowGcdDivider", "dirHeader", "reactDirAuto", "reactDirMelee",
  "grpEngine" }, "react tabBars")
onlyKeys(raRange, { "rangeHeader", "rangeFinderFindingStyle" }, "react tabRange")
onlyKeys(raGrid, { "gridHeader", "gridNote", "reactConsumablesAlways", "rcustHeader",
  "addHeader", "addType", "addId", "addProc", "addLabel", "addBtn" },
  "react tabGrid", { "rcd_", "rcust_" })
onlyKeys(raBuff, { "buffHeader", "sharedNote", "reactBuffRows", "reactBuffPositional", "reactBuffFrenzyMode", "customHeader", "customNote",
  "addBuffId", "addBuffBtn" }, "react tabBuff", { "rb_en_", "rbc_" })
onlyKeys(raSkin, { "skinHeader", "skinNote", "reactBarTexture", "reactFont", "reactFontSize",
  "reactAutoH", "reactMeleeH", "reactRangeH", "reactManaH", "reactCastH",
  "reactCornerIconSize", "reactCornerIconX", "reactCornerIconY",
  "reactColorAutoFill", "reactColorMeleeReady", "reactColorMeleeAuto", "reactColorManaFill",
  "reactColorCastFill", "reactColorRangeDeadzone", "reactColorRangeSweet", "reactColorRangePerfect",
  "reactColorRangeClose", "reactColorRangeResync", "reactRangeDividerWidth", "reactColorRangeDivider",
  "reactGcdDividerWidth", "reactColorGcdDivider",
  "autoMarksHeader", "reactTickSteadyWidth", "reactColorTickSteady",
  "reactTickMultiWidth", "reactColorTickMulti", "reactTickWindupWidth",
  "reactColorTickWindup", "reactBracketWidth", "reactColorBracket",
  "resetSkin" }, "react tabSkin")

-- Lock controls: the ONLY interactive lock controls in the tree are the two
-- pairs that drive the one global lock — General (lockAll/unlockAll) and
-- HUD → Layout (lockHud/unlockHud), the page you are on while placing things.
-- Asserting the exact key set, not just a count, is what keeps a per-panel lock
-- toggle from creeping back in under a new name.
-- Every entry here must drive the ONE global lock (Nock:SetLocked). What this
-- test exists to prevent is a per-panel lock STATE creeping back after 1.0.17
-- collapsed them; a second or third button pair pointing at the same global
-- lock is a shortcut, not a new lock, and is fine.
local ALLOWED_LOCK_KEYS = {
  lockAll = true, unlockAll = true,     -- General
  lockHud = true, unlockHud = true,     -- HUD → Layout
  lockTonk = true, unlockTonk = true,   -- Utilities → Steam Tonk (the dial is only up
                                        -- for the length of a transform, so there is
                                        -- nothing to aim its settings at until you
                                        -- unlock and it previews)
}
local lockKeys = {}
local function walk(args)
  for key, entry in pairs(args) do
    if type(entry) == "table" then
      if (entry.type == "toggle" or entry.type == "execute")
         and key:lower():find("lock", 1, true) then
        lockKeys[#lockKeys + 1] = key
      end
      if entry.args then walk(entry.args) end
    end
  end
end
walk(root)
table.sort(lockKeys)
local unexpected = {}
for _, key in ipairs(lockKeys) do
  if not ALLOWED_LOCK_KEYS[key] then unexpected[#unexpected + 1] = key end
end
ok(#unexpected == 0,
   "no lock control outside the two global pairs (stray: " .. table.concat(unexpected, ", ") .. ")")
ok(#lockKeys == 6,
   "all three global Lock/Unlock pairs present (found " .. table.concat(lockKeys, ", ") .. ")")

-- Per-panel Background styling: each floating tracker/utility panel carries
-- the HUD-depth block (fill color+opacity, LSM border style/size/color/
-- opacity). The MD tracker reuses its pre-existing mdBackgroundOpacity key.
local styled = {
  { args = child("trackers", "misdirect").args,     prefix = "md",            opacity = "mdBackgroundOpacity" },
  { args = child("trackers", "buffTracker").args,   prefix = "buffTracker" },
  { args = child("trackers", "debuffTracker").args, prefix = "debuffTracker" },
  { args = child("utilities", "shopping").args,     prefix = "shopping" },
  { args = cc,                                      prefix = "castBar" },
  { args = child("alerts", "helpers").args,         prefix = "helpers" },
}
for _, s in ipairs(styled) do
  local a, p = s.args, s.prefix
  local opacityKey = s.opacity or (p .. "BgOpacity")
  ok(a[p .. "StyleHeader"] and a[p .. "StyleHeader"].type == "header",
     p .. ": Background header present")
  ok(a[p .. "BgColor"] and a[p .. "BgColor"].type == "color", p .. ": bg color picker")
  ok(a[opacityKey] and a[opacityKey].type == "range", p .. ": bg opacity slider")
  ok(a[p .. "Border"] and a[p .. "Border"].type == "select"
     and type(a[p .. "Border"].values) == "function", p .. ": LSM border select")
  ok(a[p .. "Border"] and a[p .. "Border"].dialogControl == "Nock_LSM_Plain",
     p .. ": border select uses the plain LSM widget (font-leak guard)")
  ok(a[p .. "Border"] and a[p .. "Border"].values().None ~= nil,
     p .. ": border values keep the None sentinel")
  ok(a[p .. "BorderSize"] and a[p .. "BorderSize"].type == "range"
     and type(a[p .. "BorderSize"].disabled) == "function",
     p .. ": border thickness greys out on None")
  ok(a[p .. "BorderColor"] and a[p .. "BorderColor"].type == "color", p .. ": border color picker")
  ok(a[p .. "BorderOpacity"] and a[p .. "BorderOpacity"].type == "range", p .. ": border opacity slider")
end
-- MD must NOT grow a second opacity key — the old one is the canonical store.
ok(child("trackers", "misdirect").args.mdBgOpacity == nil,
   "md: fill opacity stays on the pre-existing mdBackgroundOpacity key")

-- Classic cast bar styling: the Background block lands below the existing
-- styling controls, plus a padding slider the other panels don't expose (the
-- inset between the panel edge and the icon/bar).
ok(cc.castBarStyleHeader and cc.castBarStyleHeader.order > cc.castBarColor.order,
   "classic cast bar: Background block sits below the styling controls")
ok(cc.castBarPadding and cc.castBarPadding.type == "range"
   and cc.castBarPadding.min == 0 and cc.castBarPadding.max == 16,
   "classic cast bar: padding slider spans 0..16")
ok(cc.castBarPadding and cc.castBarPadding.order > cc.castBarColor.order,
   "classic cast bar: padding sits in the styling section")

-- Defaults must keep reproducing each panel's pre-styling hardcoded look — a
-- drifting default silently restyles every fresh install.
dofile("Config/Defaults.lua")
local D = Nock.Defaults.profile

--------------------------------------------------------------------------------
-- R8b: the fight review ships OFF while the practice engine is being tuned, and
-- the switch that brings it back lives with the other conveyor/review settings
-- -- a flag with no control is a code change, which is exactly what it must not
-- take to turn the review back on.
--------------------------------------------------------------------------------
do
  -- Five tabs (2026-08-27, user: "prune / optimize the settings panel"): the
  -- page was 89 controls on one scroll. What a player touches is on the first
  -- tab, the engine knobs under Advanced, the colours and stage levers apart.
  local page = child("utilities", "practice")
  ok(page and page.childGroups == "tab", "practice: the page renders its groups as tabs")
  local tabs = page and page.args or {}
  local order = {}
  for id, g in pairs(tabs) do
    if type(g) == "table" and g.type == "group" then order[#order + 1] = { id = id, o = g.order } end
  end
  table.sort(order, function(a, b) return a.o < b.o end)
  local ids = {}
  for i, t in ipairs(order) do ids[i] = t.id end
  ok(table.concat(ids, ",") == "general,opener,keys,advanced,colours", "practice: tabs are Practice, Opener, Keys, Advanced, Colours & style (" .. table.concat(ids, ",") .. ")")
  local function leaves(id)
    local n = 0
    for _, o in pairs(tabs[id] and tabs[id].args or {}) do
      if o.type ~= "group" and o.type ~= "header" and o.type ~= "description" then n = n + 1 end
    end
    return n
  end
  ok(leaves("general") <= 18, "practice: the first tab holds what a player touches (" .. leaves("general") .. " controls)")
  local adv = tabs.advanced and tabs.advanced.args or {}
  ok(adv.practiceQueueWindow and adv.practiceReactionMs and adv.practiceSeed and adv.practiceConveyorPps and adv.practiceTimelinePps,
     "practice: the engine and geometry knobs sit under Advanced")
  local keys = tabs.keys and tabs.keys.args or {}
  ok(keys.practiceKeySteady and keys.practiceKeyPot, "practice: the key overrides have their own tab")
  local op = tabs.opener and tabs.opener.args or {}
  ok(op.practiceOpenerAnchor and op.practiceOpenerCds, "practice: the opener has its own tab")
  -- The review window's typed width is gone: the page sizes off its host.
  local anyWidth = false
  for _, g in pairs(tabs) do if type(g) == "table" and g.args and g.args.practiceTimelineWidth then anyWidth = true end end
  ok(not anyWidth and D.practiceTimelineWidth == nil, "practice: the review's Width (px) is gone from Options and Defaults")

  local pra = tabs.general and tabs.general.args
  ok(pra ~= nil, "practice page found")
  -- Start practice from Options closes Options (the workbench takes over);
  -- End practice leaves it up (user, 2026-08-27).
  Nock.state = Nock.state or {}
  Nock.state.sim = Nock.state.sim or {}
  STUB_CATALOGS.Practice = { Command = function() Nock.state.sim.active = not Nock.state.sim.active end }
  Nock.state.sim.active = false
  dialogClosed = 0
  pra.toggle.func()
  ok(Nock.state.sim.active == true and dialogClosed == 1, "practice: Start practice from Options closes the Options window")
  pra.toggle.func()
  ok(Nock.state.sim.active == false and dialogClosed == 1, "practice: End practice leaves Options open")
  STUB_CATALOGS.Practice = nil
  ok(pra and pra.practiceReviewEnabled and pra.practiceReviewEnabled.type == "toggle",
     "practice: the fight-review toggle is a plain checkbox on the practice page")
  ok(D.practiceReviewEnabled == false, "practice: the fight review ships OFF")
  -- Shell step 3: Focus. Start goes to Focus by default; quiet focus is off.
  ok(pra and pra.practiceFocusOnStart and pra.practiceFocusOnStart.type == "toggle"
     and pra.practiceQuietFocus and pra.practiceQuietFocus.type == "toggle",
     "practice: the two Focus toggles are on the practice page")
  ok(D.practiceFocusOnStart == false and D.practiceQuietFocus == false, "practice: Focus only when pulled out by hand, the coach line stays")
  ok(pra and pra.practiceWeaveLog == nil and D.practiceWeaveLog == false, "practice: the weave log is toggled from the shell, not Options; off by default")
  ok(pra and pra.practiceReviewEnabled and pra.timelineHeader
     and pra.practiceReviewEnabled.order > pra.timelineHeader.order,
     "practice: it sits under the Stage header on the first tab")

  -- Switching it OFF closes the review if it happens to be up. Nothing else
  -- can, once the flag is down -- every path back in is gated on it -- so a
  -- window left standing would be stuck there.
  local closed, opened = 0, 0
  STUB_CATALOGS.PracticeTimelineView = { Toggle = function(_, show)
    if show == false then closed = closed + 1 else opened = opened + 1 end
  end }
  pra.practiceReviewEnabled.set(nil, true)
  ok(Nock.db.profile.practiceReviewEnabled == true and closed == 0 and opened == 0,
     "practice: turning the review ON touches no window")
  pra.practiceReviewEnabled.set(nil, false)
  ok(Nock.db.profile.practiceReviewEnabled == false and closed == 1 and opened == 0,
     "practice: turning it OFF closes the window")
  STUB_CATALOGS.PracticeTimelineView = nil
  Nock.db.profile.practiceReviewEnabled = nil
end

--------------------------------------------------------------------------------
-- P3 polish: the stage's style levers. One select per lever, every value the
-- shared definition allows, the shipped default first -- and the defaults ARE
-- the Conveyor Skins pick, so a fresh install gets the decided look.
--------------------------------------------------------------------------------
do
  local pra = child("utilities", "practice")
  pra = pra and pra.args and pra.args.colours and pra.args.colours.args
  local T = dofile("Core/PracticeTimeline.lua")
  Nock.PracticeTimeline = T
  ok(T and T.STYLE_LEVERS and #T.STYLE_LEVERS == 9, "style: nine levers defined")
  local want = { practiceStyleNote = "glass", practiceStyleNext = "both", practiceStyleMove = "ramp",
                 practiceStyleHit = "column", practiceStylePast = "fade", practiceStyleLanes = "zebra",
                 practiceStyleAutoTick = "hairline", practiceStyleWindup = "faint", practiceStyleWindupScope = "auto" }
  for _, L in ipairs(T.STYLE_LEVERS or {}) do
    local o = pra and pra[L.key]
    ok(o and o.type == "select" and o.dialogControl ~= nil, "style: " .. L.key .. " is a plain select")
    ok(D[L.key] == L.values[1] and D[L.key] == want[L.key], "style: " .. L.key .. " ships as " .. tostring(want[L.key]))
    local vals = o and type(o.values) == "function" and o.values() or {}
    local n = 0
    for k, v in pairs(vals) do n = n + 1; ok(k == v and L.allowed[k], "style: value " .. tostring(k) .. " keyed by itself") end
    ok(n == #L.values, "style: " .. L.key .. " offers every value")
    ok(o and o.order > pra.practiceStyleHeader.order, "style: " .. L.key .. " sits under the Stage style header")
    o.set({ L.key }, L.values[2])
    ok(Nock.db.profile[L.key] == L.values[2] and o.get({ L.key }) == L.values[2], "style: set/get round-trips")
    Nock.db.profile[L.key] = nil
    ok(o.get({ L.key }) == L.values[1], "style: unset reads the default")
  end
  ok(D.practiceColorAuto and D.practiceColorAuto[1] < 0.7, "style: the auto colour ships grey")
end

--------------------------------------------------------------------------------
-- GCD divider: the toggle lives with the other auto-bar mark switches (Bars),
-- its look with the other skin knobs (Skin). It must ship OFF -- it is a line
-- sweeping across the swing bar, which changes how the HUD reads, so it is
-- opt-in like the eWS brackets rather than reference-parity-on.
--------------------------------------------------------------------------------
ok(raBars.reactShowGcdDivider and raBars.reactShowGcdDivider.type == "toggle",
   "GCD divider toggle is on the Bars subtab")
ok(D.reactShowGcdDivider == false,
   "GCD divider ships off by default")
ok(raBars.reactShowGcdDivider and raBars.reactShowBrackets
   and raBars.reactShowGcdDivider.order > raBars.reactShowBrackets.order
   and raBars.reactShowGcdDivider.order < raBars.dirHeader.order,
   "GCD divider toggle sits with the other auto-bar marks, above the direction header")
ok(raSkin.reactGcdDividerWidth and raSkin.reactGcdDividerWidth.type == "range"
   and raSkin.reactGcdDividerWidth.min == 1 and raSkin.reactGcdDividerWidth.max == 8,
   "GCD divider width is a 1-8px slider, not the 8-28px bar-height span")
ok(raSkin.reactColorGcdDivider and raSkin.reactColorGcdDivider.type == "color",
   "GCD divider colour is a colour control on the Skin subtab")
ok(raSkin.reactColorGcdDivider and raSkin.resetSkin
   and raSkin.reactColorGcdDivider.order > raSkin.reactColorRangeDivider.order
   and raSkin.reactColorGcdDivider.order < raSkin.resetSkin.order,
   "GCD divider skin rows sit after the range divider and before Reset skin")
local gcdDef = D.reactColorGcdDivider
ok(type(gcdDef) == "table" and #gcdDef == 4 and gcdDef[3] > gcdDef[1] and gcdDef[1] > gcdDef[2],
   "GCD divider default colour is purple (b > r > g)")
ok(D.reactGcdDividerWidth == 1,
   "GCD divider default width matches the other marks (1 device px)")

--------------------------------------------------------------------------------
-- Auto Shot bar marks: every mark on the React auto bar carries BOTH a width
-- and a colour, and the defaults must equal the reference constants they were
-- lifted from -- exposing a knob must not restyle anyone's bar.
--------------------------------------------------------------------------------
local AUTO_MARKS = {
  { w = "reactTickSteadyWidth", c = "reactColorTickSteady", dw = 1, dc = { 1.00, 0.10, 0.10, 1.00 } },
  { w = "reactTickMultiWidth",  c = "reactColorTickMulti",  dw = 1, dc = { 1.00, 0.65, 0.10, 1.00 } },
  { w = "reactTickWindupWidth", c = "reactColorTickWindup", dw = 1, dc = { 0.85, 0.85, 0.85, 0.80 } },
  { w = "reactBracketWidth",    c = "reactColorBracket",    dw = 1, dc = { 1.00, 1.00, 1.00, 0.35 } },
  { w = "reactGcdDividerWidth", c = "reactColorGcdDivider", dw = 1, dc = { 0.62, 0.35, 0.98, 1.00 } },
}
for i = 1, #AUTO_MARKS do
  local m = AUTO_MARKS[i]
  ok(raSkin[m.w] and raSkin[m.w].type == "range"
     and raSkin[m.w].min == 1 and raSkin[m.w].max == 8,
     m.w .. ": 1-8px slider on the Skin subtab")
  ok(raSkin[m.c] and raSkin[m.c].type == "color" and raSkin[m.c].hasAlpha,
     m.c .. ": colour control with alpha on the Skin subtab")
  ok(D[m.w] == m.dw, m.w .. ": default matches the reference constant")
  local d = D[m.c]
  local same = type(d) == "table" and #d == 4
  for k = 1, 4 do same = same and math.abs(d[k] - m.dc[k]) < 1e-9 end
  ok(same, m.c .. ": default matches the reference constant")
end

-- React must NOT have quietly adopted the classic keys: the two HUDs are styled
-- apart on purpose, so both sets exist and both carry their own widths.
for _, k in ipairs({ "clipTickSteadyColor", "clipTickMultiColor", "clipTickWindupColor" }) do
  ok(D[k] ~= nil, k .. ": classic tick colour still exists")
end
ok(D.clipTickSteadyWidth == 1 and D.clipTickMultiWidth == 1 and D.clipTickWindupWidth == 1,
   "classic clip ticks gained widths, defaulting to a 1 device-pixel hairline")

local styleDefaults = {
  { "mdBackgroundOpacity", 0.85 },        { "mdBorderOpacity", 1.0 },
  { "buffTrackerBgOpacity", 0.85 },       { "buffTrackerBorderOpacity", 1.0 },
  { "debuffTrackerBgOpacity", 0 },        { "debuffTrackerBorderOpacity", 0 },
  { "shoppingBgOpacity", 0.78 },          { "shoppingBorderOpacity", 1.0 },
  { "castBarBgOpacity", 0.85 },           { "castBarBorderOpacity", 1.0 },
  -- 4 = C.DIM.OUTER_PAD, the pre-setting hardcoded inset.
  { "castBarPadding", 4 },
  { "hideBlizzardCastBar", false },
  -- Helpers panel: 0/0 alpha reproduces the pre-styling look (no visible box);
  -- the layout numbers are the constants the view used to hardcode.
  { "helpersBgOpacity", 0 },              { "helpersBorderOpacity", 0 },
  { "helpersExpiringThreshold", 300 },
  { "helpersIconSize", 40 },              { "helpersIconGap", 10 },
  { "helpersScale", 1.0 },
  { "helpersPosition", false },
}
for _, e in ipairs(styleDefaults) do
  ok(D[e[1]] == e[2], "defaults: " .. e[1] .. " == " .. tostring(e[2]))
end
for _, p in ipairs({ "md", "buffTracker", "debuffTracker", "shopping", "castBar" }) do
  ok(D[p .. "Border"] == "None", "defaults: " .. p .. "Border is None (1px line)")
  local c = D[p .. "BgColor"]
  ok(type(c) == "table" and c[1] == 0 and c[2] == 0 and c[3] == 0,
     "defaults: " .. p .. "BgColor is black")
end

-- Per-bar TRACK styling: every classic bar exposes its own background block,
-- and every key those blocks write has a seeded default. A missing default is
-- not cosmetic here -- an option whose get() returns nil throws inside
-- AceConfigDialog's build loop, which has no pcall, so every control BELOW it
-- silently never renders (a known AceConfigDialog trap).
local trackBlocks = {
  { prefix = "castBarTrack",  page = function() return CB.castBar and CB.castBar.args end },
  { prefix = "autoShotTrack", page = function() return CB.swingBars and CB.swingBars.args end },
  { prefix = "meleeTrack",    page = function() return CB.swingBars and CB.swingBars.args end },
  { prefix = "gcdTrack",      page = function() return CB.swingBars and CB.swingBars.args end },
  { prefix = "manaTrack",     page = function() return CB.manaBar and CB.manaBar.args end },
  { prefix = "rangeTrack",    page = function() return CB.rangeFinder and CB.rangeFinder.args end },
  { prefix = "shotBarsTrack", page = function()
      local rot = CB.rotation and CB.rotation.args
      return rot and rot.grpShotBars and rot.grpShotBars.args
    end },
}
for _, b in ipairs(trackBlocks) do
  local args = b.page() or {}
  ok(args[b.prefix .. "TrackHeader"] and args[b.prefix .. "TrackHeader"].type == "header",
     b.prefix .. ": background section header present on its page")
  for _, suffix in ipairs({ "BgColor", "BgOpacity", "BorderColor", "BorderOpacity" }) do
    local key = b.prefix .. suffix
    local opt = args[key]
    ok(opt ~= nil, b.prefix .. ": " .. suffix .. " control present")
    ok(D[key] ~= nil, b.prefix .. ": " .. suffix .. " has a seeded default")
    -- get() must survive a profile that has never touched the key -- the
    -- AceConfigDialog build loop is where a nil would take the page down.
    if opt and opt.get then
      local saved = Nock.db.profile[key]
      Nock.db.profile[key] = nil
      local got = opt.get({})
      ok(got ~= nil, b.prefix .. ": " .. suffix .. " get() survives an untouched profile")
      Nock.db.profile[key] = saved
    end
  end
  -- Defaults reproduce the old hardcoded look exactly: black track @0.85, solid
  -- black 1px edge. Anything else is a silent restyle of every existing profile.
  local c, bc = D[b.prefix .. "BgColor"], D[b.prefix .. "BorderColor"]
  ok(type(c) == "table" and c[1] == 0 and c[2] == 0 and c[3] == 0,
     b.prefix .. ": default track colour is black")
  ok(type(bc) == "table" and bc[1] == 0 and bc[2] == 0 and bc[3] == 0,
     b.prefix .. ": default border colour is black")
  ok(D[b.prefix .. "BgOpacity"] == 0.85, b.prefix .. ": default track opacity is 0.85")
  ok(D[b.prefix .. "BorderOpacity"] == 1.0, b.prefix .. ": default border opacity is 1.0")
  -- The bar track is NOT the panel block: castBar* skins the box around the
  -- cast bar, castBarTrack* skins the bar itself. Keeping the prefixes apart is
  -- the whole reason the cast bar can have both.
  ok(b.prefix ~= "castBar", b.prefix .. ": prefix distinct from the panel block")
end
-- The panel block on the cast bar page still exists alongside the track block.
ok(CB.castBar and CB.castBar.args.castBarBgColor and CB.castBar.args.castBarTrackBgColor,
   "cast bar page carries BOTH the panel background and the bar track blocks")

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
