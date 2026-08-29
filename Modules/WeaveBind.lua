-- Modules/WeaveBind.lua
-- Hold-to-melee-weave override keybind: press runs a weave-in macro, release a
-- weave-out macro, via one secure button (mechanism after Grounded by Gello).

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local WeaveBind = Nock:NewModule("WeaveBind", "AceEvent-3.0", "AceTimer-3.0", "AceConsole-3.0")
local C = Nock.Constants

local BUTTON_NAME = "NockWeaveBindButton"

local function spellNameOf(spellID)
  if GetSpellInfo then
    local n = GetSpellInfo(spellID)
    if n then return n end
  end
  if C_Spell and C_Spell.GetSpellInfo then
    local i = C_Spell.GetSpellInfo(spellID)
    if i then return i.name end
  end
  return nil
end

-- How the press/release pair works on this client:
--   * One SecureActionButtonTemplate button registered for AnyDown+AnyUp, with
--     a secure OnClick wrapper (combat-legal — it runs inside the restricted
--     environment) that swaps `macrotext` to macrotextDown / macrotextUp
--     depending on the click edge.
--   * SecureActionButton_OnClick executes the action only on the edge selected
--     by the `useOnKeyDown` attribute (nil falls back to the global
--     ActionButtonUseKeyDown CVar). The wrapper sets that attribute per edge —
--     true on press, false on release — so BOTH edges execute for this button
--     while the CVar and the rest of the action bars stay untouched. Verified
--     in the Anniversary client's own SecureTemplates.lua
--     (SecureActionButton_ShouldUseOnKeyDown); the attribute shipped with
--     retail 11.1.5 and the modernized Classic clients carry it.
--   * Grounded-era setups instead flipped the CVar from the macro bodies
--     (press → 0, release → 1), which switched EVERY action button to
--     fire-on-release mid-hold and stuck there if the release edge was lost
--     (death / alt-tab / disconnect). Nock no longer ships those /console
--     lines, but user-edited macros may still carry them — the CVar watchdog
--     below remains as a safety net for exactly that case.
--   * Practice mode neuters the key HERE rather than by unbinding it. The
--     override could only be cleared out of combat, so a mob pulling mid-drill
--     would leave the weave key dead for the whole fight (practice drops
--     `sim.active` immediately, but ApplyBind is in lockdown and cannot rebind
--     until combat ends). Instead the `practice` attribute stays set while the
--     drill runs and the wrapper swaps in the practice bodies — but only while
--     PlayerInCombat() is false, so the instant real combat starts the key runs
--     the real macro again with no rebinding at all. The practice bodies
--     (WeaveMacro.PracticeBody) are empty except for a MovePad step-out the
--     user's macros carry: the drill simulates the attack lines but reads your
--     REAL footwork, so the auto-backpedal has to keep working.
local WRAP_ONCLICK = [[
  local text
  if down then
    self:SetAttribute("useOnKeyDown", true)
    text = self:GetAttribute("macrotextDown")
  else
    self:SetAttribute("useOnKeyDown", false)
    text = self:GetAttribute("macrotextUp")
  end
  if self:GetAttribute("practice") and not PlayerInCombat() then
    text = self:GetAttribute(down and "macrotextDownPractice" or "macrotextUpPractice") or ""
  end
  self:SetAttribute("macrotext", text)
]]

-- Stale-hold escape hatch: if the insecure observer saw a down-edge more than
-- this many seconds ago with no matching release, assume the up-edge was
-- swallowed and let the watchdog restore the CVar anyway.
local HELD_STALE_SEC = 30

-- Superseded default macro bodies. Profiles that stored these exact texts are
-- migrated to the current defaults on enable; anything else the user typed is
-- left alone. ONLY the CVar-flip-era texts qualify: their /console lines are
-- unambiguously stale. The pre-Snowball attribute-era defaults
-- ("/stopcasting\n/cast Raptor Strike\n/startattack" etc.) must NOT be listed
-- — stripping the Snowball/MovePad lines back down to exactly those texts is
-- now a legitimate deliberate choice, and auto-migrating would silently revert
-- that edit on every reload.
local LEGACY_DOWNS = {
  "/stopcasting\n/cast Raptor Strike\n/startattack\n/console ActionButtonUseKeyDown 0",
}
local LEGACY_UPS = {
  "/stopattack\n/console ActionButtonUseKeyDown 1",
  "/stopattack\n/cast !Auto Shot\n/console ActionButtonUseKeyDown 1",
}

-- True when the stored macro bodies still flip the CVar themselves (legacy or
-- hand-rolled). Only then can the weave mechanism leave the CVar stuck at 0 —
-- and only then may the watchdog force it back to 1. Never match against a
-- user who runs cast-on-release (CVar 0) by deliberate choice.
local function macrosTouchCVar()
  local p = Nock.db and Nock.db.profile
  if not p then return false end
  return (p.weaveBindMacroDown or ""):find("ActionButtonUseKeyDown", 1, true) ~= nil
    or (p.weaveBindMacroUp or ""):find("ActionButtonUseKeyDown", 1, true) ~= nil
end

-- Garment-conditional support. The Anniversary client does not evaluate
-- [equipped:Shirt]-style macro conditionals (the bracket passes regardless of
-- the slot), so Nock resolves them ITSELF when applying the secure button's
-- macrotext: a line whose condition fails is dropped, a passing line keeps
-- its command with the bracket stripped. BOTH cosmetic garments are
-- supported — Shirt (body, slot 4) and Tabard (slot 19) — because diagnosis
-- of the original report showed the user's toggle garment was actually a
-- TABARD with no shirt worn at all; the slot-4 probes were honest all along.
-- Neither garment can be swapped in combat, so re-applies never hit lockdown.
local GARMENT_LOC  = { shirt = "INVTYPE_BODY",    tabard = "INVTYPE_TABARD" }
local GARMENT_SLOT = { shirt = INVSLOT_BODY or 4, tabard = INVSLOT_TABARD or 19 }

-- Equip location of an item link ("INVTYPE_BODY"/"INVTYPE_TABARD"), dual-form.
local function itemEquipLoc(link)
  if not link then return nil end
  if GetItemInfo then
    local loc = select(9, GetItemInfo(link))
    if loc then return loc end
  end
  if C_Item and C_Item.GetItemInfo then
    local loc = select(9, C_Item.GetItemInfo(link))
    if loc then return loc end
  end
  return nil
end

-- Returns the inventory slot the garment sits in, or nil — the truthy result
-- doubles as the old boolean answer for the resolver/diag callers, while the
-- auto-flip needs the slot itself.
local function garmentEquipped(g)
  local slot = GARMENT_SLOT[g]
  if slot and GetInventoryItemLink and GetInventoryItemLink("player", slot) then
    return slot
  end
  -- Robustness sweep in case the constant slot ever reads empty: any equipped
  -- item with the garment's equip location counts.
  if GetInventoryItemLink then
    for s = 0, 23 do
      if itemEquipLoc(GetInventoryItemLink("player", s)) == GARMENT_LOC[g] then
        return s
      end
    end
  end
  return nil
end

local function resolveGarmentLines(text)
  if not text or text == "" then return text end
  local lower = text:lower()
  if not (lower:find("equipped:%s*shirt") or lower:find("equipped:%s*tabard")) then
    return text
  end
  local out, first = "", true
  for line in (text .. "\n"):gmatch("(.-)\n") do
    local keep, stripped = true, line
    local g = line:match("%[%s*[Nn][Oo][Ee]quipped:%s*(%a+)%s*%]")
    if g and GARMENT_LOC[g:lower()] then
      keep = not garmentEquipped(g:lower())
      stripped = line:gsub("%[%s*[Nn][Oo][Ee]quipped:%s*%a+%s*%]%s*", " ")
    else
      g = line:match("%[%s*[Ee]quipped:%s*(%a+)%s*%]")
      if g and GARMENT_LOC[g:lower()] then
        keep = garmentEquipped(g:lower())
        stripped = line:gsub("%[%s*[Ee]quipped:%s*%a+%s*%]%s*", " ")
      end
    end
    if keep then
      if first then out = stripped; first = false
      else out = out .. "\n" .. stripped end
    end
  end
  return out
end

-- Practice mode parses the same resolved bodies the live button runs, so the
-- simulated weave key does exactly what your real one would right now.
WeaveBind.ResolveGarmentLines = resolveGarmentLines

-- True when either stored macro body carries a garment conditional — the only
-- case the equipment watcher needs to re-apply for.
local function macrosTouchGarment()
  local p = Nock.db and Nock.db.profile
  if not p then return false end
  local t = ((p.weaveBindMacroDown or "") .. "\n" .. (p.weaveBindMacroUp or "")):lower()
  return (t:find("equipped:%s*shirt") or t:find("equipped:%s*tabard")) ~= nil
end

-- Which garment the macros gate on, and in which DIRECTION. Returns
-- garment, dir where dir is "off" — [noequipped:g] lines, armed when the
-- garment is REMOVED (the shipped convention) — or "on" — [equipped:g]
-- lines, armed when it is WORN. Shirt is checked before tabard (mirrors the
-- resolver/warning order); if both forms appear for one garment the "off"
-- convention wins, since a two-way gate can't be driven automatically.
local GARMENT_ORDER = { "shirt", "tabard" }
local function gateGarment()
  local p = Nock.db and Nock.db.profile
  if not p then return nil end
  local t = ((p.weaveBindMacroDown or "") .. "\n" .. (p.weaveBindMacroUp or "")):lower()
  -- Stripping "noequipped" first leaves only the positive [equipped:...]
  -- occurrences findable ("equipped:" is a substring of "noequipped:").
  local plain = t:gsub("noequipped", "")
  for i = 1, #GARMENT_ORDER do
    local g = GARMENT_ORDER[i]
    if t:find("noequipped:%s*" .. g) then return g, "off" end
    if plain:find("equipped:%s*" .. g) then return g, "on" end
  end
  return nil
end

-- Dual-form bag/equip APIs for the garment autopilot (the modernized client
-- keeps these under C_Container / C_Item; older builds expose bare globals).
local function containerFreeSlots(bag)
  if C_Container and C_Container.GetContainerNumFreeSlots then
    return C_Container.GetContainerNumFreeSlots(bag)
  elseif GetContainerNumFreeSlots then
    return GetContainerNumFreeSlots(bag)
  end
  return 0, 0
end

local function containerNumSlots(bag)
  if C_Container and C_Container.GetContainerNumSlots then
    return C_Container.GetContainerNumSlots(bag)
  elseif GetContainerNumSlots then
    return GetContainerNumSlots(bag)
  end
  return 0
end

local function containerItemLink(bag, slotIdx)
  if C_Container and C_Container.GetContainerItemLink then
    return C_Container.GetContainerItemLink(bag, slotIdx)
  elseif GetContainerItemLink then
    return GetContainerItemLink(bag, slotIdx)
  end
  return nil
end

-- First shirt/tabard sitting in the bags, for the [equipped:...] direction
-- (the garment must go ON for the boss). Returns itemID, link or nil.
local function findGarmentInBags(g)
  for bag = 0, 4 do
    for i = 1, containerNumSlots(bag) or 0 do
      local link = containerItemLink(bag, i)
      if link and itemEquipLoc(link) == GARMENT_LOC[g] then
        local id = tonumber(link:match("item:(%d+)"))
        if id then return id, link end
      end
    end
  end
  return nil
end

-- Stow the item on the cursor into the given bag (0 = backpack). Returns
-- false when no API form exists at all.
local function putCursorItemInBag(bag)
  if bag == 0 then
    local put = (C_Container and C_Container.PutItemInBackpack) or PutItemInBackpack
    if put then put() return true end
    return false
  end
  local toInv = (C_Container and C_Container.ContainerIDToInventoryID) or ContainerIDToInventoryID
  local put   = (C_Container and C_Container.PutItemInBag) or PutItemInBag
  if toInv and put then put(toInv(bag)) return true end
  return false
end

local function equipItemByID(itemID)
  local equip = (C_Item and C_Item.EquipItemByName) or EquipItemByName
  if equip then equip(itemID) return true end
  return false
end

-- A raid boss (mirrors Modules/Warnings.lua): an attackable, alive target
-- classified "worldboss" or boss-level (UnitLevel == -1, the ?? skull).
local function isBossTarget()
  if not (UnitExists and UnitExists("target")) then return false end
  if UnitCanAttack and not UnitCanAttack("player", "target") then return false end
  if UnitIsDead and UnitIsDead("target") then return false end
  if UnitClassification and UnitClassification("target") == "worldboss" then return true end
  if UnitLevel and UnitLevel("target") == -1 then return true end
  return false
end

-- Deferred-apply frame. A bare frame (not AceEvent) on purpose: if the module
-- is disabled mid-combat, AceEvent unregisters the module's own events, but
-- this frame still replays the teardown once combat ends.
local regenWaiter
local function ensureRegenWaiter()
  if regenWaiter then return regenWaiter end
  regenWaiter = CreateFrame("Frame")
  regenWaiter:SetScript("OnEvent", function(f)
    f:UnregisterEvent("PLAYER_REGEN_ENABLED")
    WeaveBind:ApplyBind()
  end)
  return regenWaiter
end

-- Note practice mode is deliberately NOT a factor here: the override stays
-- bound while the drill runs and the secure wrapper blanks the macro instead
-- (see WRAP_ONCLICK). Unbinding would strand the key for a whole fight when
-- combat interrupts practice.
local function featureActive()
  local p = Nock.db and Nock.db.profile
  return WeaveBind:IsEnabled() and p and p.weaveBindEnabled == true
    and (p.weaveBindKey or "") ~= ""
end

function WeaveBind:OnEnable()
  -- One-time migration: stored CVar-flip-era default texts fall back to the
  -- current (attribute-mechanism) defaults. nil lets the AceDB default show.
  local p = Nock.db and Nock.db.profile
  if p then
    for i = 1, #LEGACY_DOWNS do
      if p.weaveBindMacroDown == LEGACY_DOWNS[i] then p.weaveBindMacroDown = nil end
    end
    for i = 1, #LEGACY_UPS do
      if p.weaveBindMacroUp == LEGACY_UPS[i] then p.weaveBindMacroUp = nil end
    end
    -- Stock bodies are brought up to date, custom ones never touched
    -- (WM.IsNockAuthored tells them apart): the release re-arm (2026-08-27)
    -- on a release body Nock wrote whose press body already gates the poke.
    local WM = Nock.WeaveMacro
    if WM and WM.SyncRearmIfStock and WM.SyncRearmIfStock(p, C.WEAVE_BIND_MACRO_UP) then
      self:Print("Weave Bind: your release macro gained the re-arm (/startattack gated the other way round from the poke). It is still Nock's stock macro; edit it and Nock leaves it alone.")
    end
  end
  self:RegisterMessage("NOCK_WEAVEBIND_CHANGED", "ApplyBind")
  self:RegisterMessage("NOCK_PRACTICE_CHANGED", "ApplyBind")
  self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnRegenEnabled")
  self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnEnteringWorld")
  self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", "OnEquipmentChanged")
  self:RegisterEvent("PLAYER_TARGET_CHANGED", "OnTargetChanged")
  self:ApplyBind()
end

function WeaveBind:OnDisable()
  -- Events/timers are auto-unregistered by AceEvent/AceTimer. Tear down the
  -- binding; in combat this defers via the bare regenWaiter frame above.
  self.watchdog = nil
  self:ApplyBind()
end

-- Body-slot changes re-resolve any shirt-conditional macro lines. Gated to
-- the body slot so mid-combat weapon swaps don't churn the (combat-deferred)
-- apply path.
function WeaveBind:OnEquipmentChanged(_, slot)
  if (slot == GARMENT_SLOT.shirt or slot == GARMENT_SLOT.tabard)
     and macrosTouchGarment() then
    -- The gate slot REVERSING while the autopilot memo still exists — worn
    -- again after an "off" arm, or bare again after an "on" arm — means the
    -- USER did it (our own restore clears the memo before acting): honor
    -- that and stand down while this boss stays targeted.
    local memo = Nock.db.char.garmentFlip
    if memo and slot == memo.slot then
      local worn = GetInventoryItemLink and GetInventoryItemLink("player", slot) ~= nil
      if ((memo.dir or "off") == "off" and worn) or (memo.dir == "on" and not worn) then
        Nock.db.char.garmentFlip = false
        self._overrideGUID = UnitGUID and UnitGUID("target") or nil
      end
    end
    self:ApplyBind()
  end
end

function WeaveBind:OnRegenEnabled()
  -- Combat end is a natural recovery point for a stuck CVar or a stuck
  -- MovePad toggle (died mid-hold). Also the main re-equip edge for the
  -- garment auto-flip: kill and wipe both end here, and a boss that dies
  -- while still targeted fires no PLAYER_TARGET_CHANGED.
  self:Watchdog()
  self:GarmentFlipCheck()
end

function WeaveBind:OnTargetChanged()
  -- New target: the manual-override latch, the blocked note, and the
  -- warned-once latches were all about the previous one.
  local guid = UnitGUID and UnitGUID("target") or nil
  if guid ~= self._overrideGUID then self._overrideGUID = nil end
  Nock.state.weave.garmentFlipBlocked = false
  self._bagFullWarned = nil
  self._noGarmentWarned = nil
  self:GarmentFlipCheck()
end

function WeaveBind:OnEnteringWorld()
  -- Reload/zone-in mid-hold: the release edge is gone for good.
  Nock.state.weave.keyHeld = false
  self:Watchdog()
  self:ApplyBind()
end

function WeaveBind:EnsureButton()
  if self.button then return self.button end
  local button = CreateFrame("Button", BUTTON_NAME, nil, "SecureActionButtonTemplate")
  -- Both edges must be REGISTERED for OnClick to fire at all; which edge then
  -- EXECUTES the action is decided per click by the useOnKeyDown attribute the
  -- wrapper sets (see WRAP_ONCLICK).
  button:RegisterForClicks("AnyDown", "AnyUp")
  button:SetAttribute("type", "macro")
  SecureHandlerWrapScript(button, "OnClick", button, WRAP_ONCLICK)
  -- Insecure post-hook (taint-safe alongside secure handlers): tracks the held
  -- state for the watchdog and the weave coach (state.weave). After a release,
  -- double-check the CVar shortly — a no-op unless the user's macros still
  -- flip it themselves (see macrosTouchCVar).
  button:HookScript("OnClick", function(_, btn, down)
    if Nock.state.sim.active then
      -- Practice owns the weave key: the wrapper blanked the macro, the edge
      -- drives the simulated weave instead.
      local pr = Nock:GetModule("Practice", true)
      if pr and pr.OnWeaveEdge then pr:OnWeaveEdge(down) end
      return
    end
    -- /nock weavelog full: count + print every edge the secure button gets, to
    -- localize lost presses (input never delivered vs delivered-but-no-effect).
    -- Prints the hold duration on each UP: a hold under ~100ms is far too
    -- short for a real weave and flags switch bounce (instant down-up pairs
    -- from a worn microswitch cancel the weave-in before the swing happens).
    -- Metrics-only mode skips all of this — the delay metrics live in the
    -- CLEU watcher below.
    if Nock._weaveLog == "full" then
      local now = GetTime()
      if down then
        Nock._weaveLogN = (Nock._weaveLogN or 0) + 1
        local sinceLast = Nock._weaveLogDownT and (now - Nock._weaveLogDownT) or nil
        Nock._weaveLogDownT = now
        -- Why-was-this-slow context: melee swing recharge left at the press
        -- (the server won't land a hit until it reaches 0), range zone at the
        -- press (travel time still ahead?), and current ping (the floor).
        local st = Nock.state
        local meleeLeft = (st.melee and st.melee.swingRemaining or 0)
        local zone = (st.target and st.target.rangeZone) or "?"
        local ping = (st.network and st.network.latencyMs) or 0
        -- Supply check: the shipped press macro burns a Snowball per weave —
        -- running dry silently degrades back to retry-pulse luck, so keep the
        -- remaining count in every DOWN line while the macro references it.
        local snow = ""
        local pDown = Nock.db.profile.weaveBindMacroDown or ""
        if pDown:find("Snowball", 1, true) and GetItemCount then
          snow = (", snowballs %d"):format(GetItemCount(C.SNOWBALL_ITEM) or 0)
        end
        -- Shirt-gated macros: log what the resolver saw, so a mis-armed
        -- Snowball line is diagnosable from the log alone.
        if pDown:lower():find("equipped:%s*shirt") then
          snow = snow .. (garmentEquipped("shirt") and ", shirt ON" or ", shirt OFF")
        end
        if pDown:lower():find("equipped:%s*tabard") then
          snow = snow .. (garmentEquipped("tabard") and ", tabard ON" or ", tabard OFF")
        end
        self:Log(("weavelog: DOWN #%d (%s) meleeCD %.0fms, zone %s, ping %dms%s%s"):format(
          Nock._weaveLogN, tostring(btn),
          math.max(0, meleeLeft) * 1000, tostring(zone), ping, snow,
          (sinceLast and sinceLast < 0.15) and (" — %.0fms after previous down, BOUNCE?"):format(sinceLast * 1000) or ""))
      else
        local held = Nock._weaveLogDownT and (now - Nock._weaveLogDownT) or 0
        -- The decisive per-hold fact: did this pass EVER reach true melee
        -- (Wing Clip) range? Position at the release itself is misleading —
        -- a good weave has already stepped back out by the up-edge.
        local w2 = Nock.state.weave
        local touched = w2.holdTouchedMelee
        local inMs = (w2.holdMeleeSec or 0) * 1000
        self:Log(("weavelog: UP   #%d (%s) held %.0fms — %s%s"):format(
          Nock._weaveLogN or 0, tostring(btn), held * 1000,
          touched and ("in melee ~%.0fms%s"):format(inMs, inMs < 120 and " (GRAZE — server likely never agreed)" or "")
            or "NEVER reached melee (turned early?)",
          (held > 0 and held < 0.1) and " — TOO SHORT, weave-out cancelled the weave-in (bounce?)" or ""))
      end
    end
    local w = Nock.state.weave
    -- Retry-grid verifier (M1): stamp the predicted reactivation cost at every
    -- release edge while ANY weavelog mode runs; OnWeaveLogCLEU prints the
    -- predicted-vs-measured pair when the reactivated auto actually fires.
    -- This is the in-game gate for Nock.ReleaseCost — the release bar promises
    -- whatever this measures.
    if Nock._weaveLog and not down then
      Nock._wvPredictedCost = w.releaseCost or 0
    end
    if down then
      self._sawDown = true
      -- keyHeldSince must mean the FIRST down-edge of the hold: the weave
      -- coach compares the melee swing stamp against it, and a repeated down
      -- click mid-hold (key repeat, /click) re-stamping it would flip the
      -- coach's "hit landed" verdict back to false.
      if not w.keyHeld then
        w.keyHeld = true
        w.keyHeldSince = GetTime()
        w.holdTouchedMelee = false  -- per-hold breadcrumbs, set by WeaveCoach
        w.holdMeleeSec = 0
      end
    else
      w.keyHeld = false
      self:ScheduleTimer("Watchdog", 1)
    end
  end)
  self.button = button
  return button
end

-- Every weavelog chat line also lands in a capture buffer while a session is
-- armed (SetLogging(true) resets it; stopping keeps it, so a report can be
-- pulled after the fight). Buffered copies carry a session-relative stamp;
-- the chat line stays raw. Capped by dropping the OLDEST lines — the tail of
-- a long session is the part worth pasting.
WeaveBind.LOG_MAX = 500

function WeaveBind:Log(line)
  -- The chat line and the buffer belong to a /nock weavelog session; the
  -- metrics-only registration (the weave log panel) keeps quiet.
  if self._wvQuiet then return end
  Nock:Print(line)
  local buf = self._wvBuf
  if not buf then return end
  buf[#buf + 1] = ("[%6.1fs] %s"):format(GetTime() - (self._wvT0 or 0), line)
  while #buf > WeaveBind.LOG_MAX do table.remove(buf, 1) end
end

-- The copybox text: one context header (chat can't be copied; the header
-- carries what a pasted log needs to be interpretable) plus every captured
-- line. nil when there is nothing worth a box.
function WeaveBind:BuildReport()
  local buf = self._wvBuf
  if not buf or #buf == 0 then return nil end
  local st = Nock.state
  local ver = (C_AddOns and C_AddOns.GetAddOnMetadata
               and C_AddOns.GetAddOnMetadata("Nock", "Version")) or "?"
  local head = ("Nock v%s weave log — %d lines, eWS %.2fs, windup %.3fs, latency %dms"):format(
    ver, #buf,
    (st.ranged and st.ranged.swingDuration) or 0,
    (st.ranged and st.ranged.windup) or 0,
    (st.network and st.network.latencyMs) or 0)
  return head .. "\n" .. string.rep("-", 40) .. "\n" .. table.concat(buf, "\n")
end

-- /nock weavelog report. Plain text in the shared copy box, /nock diag style.
function WeaveBind:ShowReport()
  local text = self:BuildReport()
  if not text then
    Nock:Print("weavelog: nothing captured — /nock weavelog starts a logging session first.")
    return
  end
  if Nock.UI and Nock.UI.ShowCopyBox then
    Nock.UI.ShowCopyBox(text)
  else
    Nock:Print(text)
  end
end

-- /nock weavelog outcome tracking: while logging, watch the combat log for
-- the player's melee swings and Raptor Strikes (hits AND avoidance — a dodge/
-- parry/miss produces no damage yet consumed the weave) and print each with
-- its offset from the last down-edge. Registered only while logging.
-- THE WEAVE LOG PANEL'S SOURCE (UI/Frame_PracticeWeaveLog.lua): the same
-- weave-delay measurement, registered without a logging session -- no chat,
-- no buffer -- publishing one structured entry per weave to
-- Nock.state.weave.entries (newest last, WEAVE_ENTRIES kept): t, name (the
-- melee), a2w, w2a, total, plus the retry-grid cost of the release that
-- followed when SwingTimer measured one. A new combat starts the list over.
WeaveBind.WEAVE_ENTRIES = 24

function WeaveBind:SetMetrics(on)
  if on == (self._wvMetrics or false) then return end
  self._wvMetrics = on
  if on then
    if not Nock._weaveLog then self:SetLogging(true); self._wvBuf = nil; self._wvQuiet = true end
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnWeaveLogCombat")
  else
    self:UnregisterEvent("PLAYER_REGEN_DISABLED")
    self._wvQuiet = nil
    if not Nock._weaveLog then self:SetLogging(false) end
  end
end

function WeaveBind:OnWeaveLogCombat()
  local w = Nock.state.weave
  w.entries = w.entries or {}
  for i = #w.entries, 1, -1 do w.entries[i] = nil end
  w.entriesN = 0
  w.combatAt = GetTime()
end

-- `from` / `to`: the ranged casts that bracketed the weave, by name (the
-- weave log's tooltip says which ability closed it).
function WeaveBind:PushWeave(name, a2w, w2a, total, now, from, to)
  local w = Nock.state.weave
  local list = w.entries
  if not list then list = {}; w.entries = list end
  list[#list + 1] = { t = now, name = name, a2w = a2w, w2a = w2a, total = total, from = from, to = to }
  while #list > WeaveBind.WEAVE_ENTRIES do table.remove(list, 1) end
  w.entriesN = (w.entriesN or 0) + 1
end

function WeaveBind:SetLogging(on)
  if on then
    -- Fresh capture session; stopping (below) leaves the buffer for a
    -- post-fight /nock weavelog report.
    if Nock._weaveLog then self._wvQuiet = nil end
    self._wvBuf, self._wvT0 = {}, GetTime()
    self.playerGUID = UnitGUID("player")
    self._raptorName = spellNameOf(C.SpellID.RAPTOR_STRIKE)
    self._autoName = spellNameOf(C.SpellID.AUTO_SHOT)
    Nock._wvPredictedCost = nil
    -- Ranged "casts" for the weave-delay metrics (the aerthax/weave-delay
    -- definitions, so numbers are comparable with its WCL analysis). Both
    -- halves measure DEAD TIME — time the player was free to act — so they
    -- anchor on opposite edges of a cast:
    --   ability→weave = last ranged cast COMPLETES → melee event
    --   weave→ability = melee event → next ranged cast STARTS
    --   total         = the sum, i.e. the gap between two shots
    -- Anchoring the second half on the completion instead would bill Steady's
    -- / Multi's whole cast time to the weave.
    self._rangedNames = {}
    for _, id in ipairs({ C.SpellID.AUTO_SHOT, C.SpellID.STEADY_SHOT,
                          C.SpellID.MULTI_SHOT, C.SpellID.ARCANE_SHOT }) do
      local n = spellNameOf(id)
      if n then self._rangedNames[n] = true end
    end
    self._wvLastRangedT, self._wvLastRangedName = nil, nil
    self._wvMeleeT, self._wvA2W, self._wvMeleeName = nil, nil, nil
    -- Per-name "this cast already announced a START" flag, so the matching
    -- SPELL_CAST_SUCCESS doesn't close the same weave a second time.
    self._wvStarted = {}
    self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", "OnWeaveLogCLEU")
    self:RegisterEvent("UI_ERROR_MESSAGE", "OnWeaveLogError")
  else
    self:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    self:UnregisterEvent("UI_ERROR_MESSAGE")
  end
end

-- A melee event in the weave-delay sense (white swing or Raptor, hit or
-- avoided). Stamps ability→weave against the last ranged cast; the pending
-- half completes when the next ranged cast arrives.
function WeaveBind:WeaveDelayMelee(name)
  local now = GetTime()
  if self._wvLastRangedT then
    self._wvA2W = now - self._wvLastRangedT
    self:Log(("weavelog:   ability->weave %.0fms (%s -> %s)"):format(
      self._wvA2W * 1000, tostring(self._wvLastRangedName), name))
  end
  self._wvMeleeT, self._wvMeleeName = now, name
end

-- Close the pending weave against the START of the next ranged cast. `now` is
-- passed in rather than read here so the caller decides which edge counts:
-- SPELL_CAST_START for anything with a cast bar or wind-up (Steady, Multi,
-- the Auto Shot wind-up), SPELL_CAST_SUCCESS for instants that never emit one.
function WeaveBind:WeaveDelayClose(name, now)
  if not self._wvMeleeT then return end
  local w2a = now - self._wvMeleeT
  local total = self._wvA2W and (self._wvA2W + w2a) or nil
  self:Log(("weavelog:   weave->ability %.0fms (%s -> %s)%s"):format(
    w2a * 1000, tostring(self._wvMeleeName), tostring(name),
    total and (" — TOTAL WEAVE %.0fms"):format(total * 1000) or ""))
  self:Log("weavelog: --------------------------------")
  self:PushWeave(self._wvMeleeName, self._wvA2W, w2a, total, self._wvMeleeT, self._wvLastRangedName, name)
  self._wvMeleeT, self._wvA2W, self._wvMeleeName = nil, nil, nil
end

-- Server rejections during a hold ("Out of range.", "You are facing the
-- wrong way!") are the smoking gun for client-probe vs server-reach
-- disagreements — print them stamped against the down-edge.
function WeaveBind:OnWeaveLogError(_, _, msg)
  if Nock._weaveLog ~= "full" then return end
  if not Nock.state.weave.keyHeld then return end
  local downT = Nock._weaveLogDownT
  local off = downT and ((GetTime() - downT) * 1000) or 0
  self:Log(("weavelog:   ERROR +%.0fms: %s"):format(off, tostring(msg)))
end

function WeaveBind:OnWeaveLogCLEU()
  local _, sub, _, srcGUID, _, _, _, _, _, _, _, a12, a13, _, a15 =
    CombatLogGetCurrentEventInfo()
  if srcGUID ~= self.playerGUID then return end
  local full = (Nock._weaveLog == "full")
  local downT = Nock._weaveLogDownT
  local off = downT and ((GetTime() - downT) * 1000) or 0
  if sub == "SWING_DAMAGE" then
    if full then
      self:Log(("weavelog:   SWING hit +%.0fms (%s dmg)"):format(off, tostring(a12)))
    end
    self:WeaveDelayMelee("Melee")
  elseif sub == "SWING_MISSED" then
    if full then
      self:Log(("weavelog:   SWING %s +%.0fms"):format(tostring(a12), off))
    end
    self:WeaveDelayMelee("Melee")
  elseif (sub == "SPELL_DAMAGE" or sub == "SPELL_MISSED") and a13 == self._raptorName then
    if full then
      if sub == "SPELL_DAMAGE" then
        self:Log(("weavelog:   RAPTOR hit +%.0fms (%s dmg)"):format(off, tostring(a15)))
      else
        self:Log(("weavelog:   RAPTOR %s +%.0fms"):format(tostring(a15), off))
      end
    end
    self:WeaveDelayMelee("Raptor Strike")
  elseif sub == "SPELL_CAST_START" and self._rangedNames and self._rangedNames[a13] then
    -- The weave is over the instant the cast BEGINS — Steady/Multi lock the
    -- player out from here, and the Auto Shot wind-up needs them at range.
    -- Flag it so the matching SUCCESS doesn't close the same weave again.
    self._wvStarted[a13] = true
    self:WeaveDelayClose(a13, GetTime())
  elseif sub == "SPELL_CAST_SUCCESS" and self._rangedNames and self._rangedNames[a13] then
    local now = GetTime()
    if self._wvStarted[a13] then
      self._wvStarted[a13] = nil   -- tail of a cast already closed at its START
    else
      self:WeaveDelayClose(a13, now)   -- instant (Arcane Shot): no START edge
    end
    -- Either way the next ability→weave window opens on COMPLETION: that's the
    -- moment the player is free to step in again.
    self._wvLastRangedT, self._wvLastRangedName = now, a13
    -- Retry-grid verifier (M1): the auto after a logged release edge fired.
    -- Predicted is Nock.ReleaseCost at the up-edge; measured is SwingTimer's
    -- autoDelay for this very shot. Printed a breath later so SwingTimer's own
    -- CLEU handler has stamped autoDelay regardless of handler order. On a
    -- dummy, a run of these pairs IS the sawtooth check — if they track, the
    -- release bar's promise holds on this client; if not, the model is wrong.
    if Nock._wvPredictedCost and a13 == self._autoName then
      local predicted = Nock._wvPredictedCost
      Nock._wvPredictedCost = nil
      C_Timer.After(0.05, function()
        self:Log(("weavelog:   release->auto predicted +%.0fms, measured +%.0fms"):format(
          predicted * 1000, (Nock.state.ranged.autoDelay or 0) * 1000))
      end)
    end
  end
end

-- /click MovePadBackward is an optional user-added step-out (no longer in
-- the shipped defaults). The Movement Pad is a LoadOnDemand Blizzard
-- accessibility addon; when the stored macros reference it, make sure its
-- buttons exist (loading it does NOT show the pad — /click works on the
-- hidden buttons) and warn once if they can't be produced, because the
-- /click line would otherwise fail silently and the weave quietly loses its
-- step-out.
function WeaveBind:EnsureMovePad()
  local p = Nock.db.profile
  local uses = ((p.weaveBindMacroDown or ""):find("MovePad", 1, true) ~= nil)
    or ((p.weaveBindMacroUp or ""):find("MovePad", 1, true) ~= nil)
  if not uses or _G.MovePadBackward then return end
  if C_AddOns and C_AddOns.LoadAddOn then
    pcall(C_AddOns.LoadAddOn, "Blizzard_MovePad")
  end
  if not _G.MovePadBackward and not self._movePadWarned then
    self._movePadWarned = true
    self:Print("Weave Bind: the macro uses /click MovePadBackward, but the Movement Pad isn't available on this client — that line will do nothing. Enable the Movement Pad in the game's interface/accessibility options, then /reload.")
  end
end

-- Copy-paste window for diagnostics: a multiline EditBox with the dump
-- pre-highlighted (Ctrl+C, Esc closes). Chat output can't be copied in the
-- client, so anything meant to be pasted back for debugging goes here.
local copyBox
local function showCopyBox(text)
  if not copyBox then
    local f = CreateFrame("Frame", "NockWeaveDiagCopy", UIParent, "BackdropTemplate")
    f:SetSize(560, 300)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({
      bgFile   = "Interface\\Buttons\\WHITE8X8",
      edgeFile = "Interface\\Buttons\\WHITE8X8",
      edgeSize = 1,
    })
    f:SetBackdropColor(0, 0, 0, 0.95)
    f:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -8)
    title:SetText("Nock diagnostic — Ctrl+C to copy, Esc to close")
    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -28)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -30, 10)
    local eb = CreateFrame("EditBox", nil, scroll)
    eb:SetMultiLine(true)
    eb:SetFontObject(ChatFontNormal)
    eb:SetWidth(510)
    eb:SetAutoFocus(true)
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    scroll:SetScrollChild(eb)
    f.editBox = eb
    copyBox = f
  end
  copyBox.editBox:SetText(text)
  copyBox:Show()
  copyBox.editBox:SetFocus()
  copyBox.editBox:HighlightText()
end

-- /nock shirt: one-shot diagnostics for the shirt-conditional resolver —
-- every equipped-probe's answer, the resolver verdict, whether the stored
-- macros carry the conditional, and the applied vs stored press macro, so a
-- mis-armed Snowball line is attributable from a single paste. Shown in a
-- copyable window (plus a short chat note).
function WeaveBind:DumpShirtDiag()
  local slot = INVSLOT_BODY or 4
  local id  = GetInventoryItemID and GetInventoryItemID("player", slot)
  local lnk = GetInventoryItemLink and GetInventoryItemLink("player", slot)
  local tex = GetInventoryItemTexture and GetInventoryItemTexture("player", slot)
  local cItem = "absent"
  if C_Item and C_Item.DoesItemExist and ItemLocation
     and ItemLocation.CreateFromEquipmentSlot then
    local ok, loc = pcall(ItemLocation.CreateFromEquipmentSlot, ItemLocation, slot)
    if ok and loc then
      cItem = "exists=" .. tostring(C_Item.DoesItemExist(loc))
    else
      cItem = "errored"
    end
  end
  local p = Nock.db and Nock.db.profile
  local lines = {
    "Nock shirt diag",
    ("slot: %d (INVSLOT_BODY=%s)"):format(slot, tostring(INVSLOT_BODY)),
    ("GetInventoryItemID:      %s -> %s"):format(GetInventoryItemID and "ok" or "NIL", tostring(id)),
    ("GetInventoryItemLink:    %s -> %s"):format(GetInventoryItemLink and "ok" or "NIL", tostring(lnk)),
    ("GetInventoryItemTexture: %s -> %s"):format(GetInventoryItemTexture and "ok" or "NIL", tostring(tex)),
    ("C_Item equipment probe:  %s"):format(cItem),
    ("resolver verdict: shirt %s, tabard %s"):format(
      garmentEquipped("shirt") and "ON" or "OFF",
      garmentEquipped("tabard") and "ON" or "OFF"),
    ("macros carry conditional: %s"):format(macrosTouchGarment() and "yes" or "NO"),
    ("feature active: %s"):format(featureActive() and "yes" or "NO"),
    "--- equipped slot sweep (0-23) ---",
  }
  if GetInventoryItemLink then
    for s = 0, 23 do
      local l = GetInventoryItemLink("player", s)
      if l then
        -- Escape the link's control codes so the copy box shows readable text.
        lines[#lines + 1] = ("slot %d: %s (%s)"):format(
          s, l:gsub("|", "||"), tostring(itemEquipLoc(l)))
      end
    end
  else
    lines[#lines + 1] = "GetInventoryItemLink NIL — sweep unavailable"
  end
  lines[#lines + 1] = "--- STORED press macro ---"
  lines[#lines + 1] = tostring(p and p.weaveBindMacroDown)
  lines[#lines + 1] = "--- APPLIED press macro (what the button runs) ---"
  lines[#lines + 1] = tostring(self.button and self.button:GetAttribute("macrotextDown"))
  local text = table.concat(lines, "\n")
  showCopyBox(text)
  self:Print("shirt diag opened — Ctrl+C the highlighted text.")
end

-- Single reconcile function: profile/enable state in, binding + watchdog out.
-- Everything that changes the feature funnels through here (options setters
-- send NOCK_WEAVEBIND_CHANGED).
-- `msg` is the AceEvent message name when this runs as a message handler; it
-- is nil for the direct calls (OnEnable, OnDisable, the regen waiter).
function WeaveBind:ApplyBind(msg)
  if InCombatLockdown() then
    ensureRegenWaiter():RegisterEvent("PLAYER_REGEN_ENABLED")
    -- Say so, once per combat: the secure button's attributes can't be
    -- rewritten in lockdown, so a macro edit saved mid-fight keeps running
    -- the OLD text until combat ends — invisible and very confusing without
    -- this line ("I removed the line but it still fires").
    -- NOT for the practice refresh: nothing the user typed is waiting there,
    -- and the wrapper's PlayerInCombat() check already hands the key back the
    -- moment combat starts — the line would only be a lie.
    if not self._deferNotified and msg ~= "NOCK_PRACTICE_CHANGED" then
      self._deferNotified = true
      self:Print("Weave Bind: in combat — your changes are saved and will apply when combat ends.")
    end
    return
  end
  self._deferNotified = nil
  local p = Nock.db.profile
  if self.button then ClearOverrideBindings(self.button) end
  if featureActive() then
    self:EnsureMovePad()
    local button = self:EnsureButton()
    button:SetAttribute("macrotextDown", resolveGarmentLines(p.weaveBindMacroDown or ""))
    button:SetAttribute("macrotextUp",   resolveGarmentLines(p.weaveBindMacroUp or ""))
    -- The drill's state, read by the secure wrapper on every click: while
    -- practice is on (and out of combat) the button runs the practice bodies —
    -- just the MovePad step-out, if the macros carry one and the drill reads
    -- real footwork. Attribute writes are out-of-combat only, which this path
    -- already is.
    local WM, footwork = Nock.WeaveMacro, p.practiceFootwork or "move"
    button:SetAttribute("macrotextDownPractice", WM.PracticeBody(p.weaveBindMacroDown, footwork))
    button:SetAttribute("macrotextUpPractice",   WM.PracticeBody(p.weaveBindMacroUp, footwork))
    button:SetAttribute("practice", Nock.state.sim.active and true or false)
    SetOverrideBindingClick(button, true, p.weaveBindKey, BUTTON_NAME)
    if not self.watchdog then
      self.watchdog = self:ScheduleRepeatingTimer("Watchdog", 5)
    end
    -- Covers "auto-flip toggled on with a boss already targeted" and profile
    -- switches. Deferred one-shot so the flip's own equipment event (which
    -- funnels back through ApplyBind) can't recurse; the check itself is
    -- idempotent, so the second pass is a no-op.
    self:ScheduleTimer("GarmentFlipCheck", 0.1)
  else
    if self.watchdog then
      self:CancelTimer(self.watchdog)
      self.watchdog = nil
    end
    Nock.state.weave.keyHeld = false
    self:VerifyCVar()
  end
end

-- Shared verifier: the legacy CVar check and the MovePad toggle check ride
-- the same cadence (5s repeating while active, 1s after each release, combat
-- end, world entry).
function WeaveBind:Watchdog()
  self:VerifyCVar()
  self:VerifyMovePad()
  self:VerifyGarmentLines()
  -- Auto-flip retry loop: bags-full recovery, running back after a wipe,
  -- missed target-change edges.
  self:GarmentFlipCheck()
end

-- Belt-and-suspenders for the shirt-conditional resolver: if the equipment
-- event ever fails to fire on this client, the watchdog notices the applied
-- macrotext no longer matches the freshly-resolved profile text and
-- re-applies within 5s. Out of combat only (attribute writes are blocked in
-- lockdown; shirts can't change in combat anyway).
function WeaveBind:VerifyGarmentLines()
  if not macrosTouchGarment() then return end
  if InCombatLockdown and InCombatLockdown() then return end
  if not (self.button and featureActive()) then return end
  local p = Nock.db.profile
  if self.button:GetAttribute("macrotextDown") ~= resolveGarmentLines(p.weaveBindMacroDown or "")
     or self.button:GetAttribute("macrotextUp") ~= resolveGarmentLines(p.weaveBindMacroUp or "") then
    self:ApplyBind()
  end
end

-- ---------------------------------------------------------------------------
-- Garment gate autopilot. With weaveBindGarmentAutoFlip on and a garment
-- conditional in the macros, Nock puts the gate garment into its BOSS state
-- when a raid boss is targeted out of combat — takes it off for
-- [noequipped:...] lines, puts it on for [equipped:...] lines — and, gated
-- on weaveBindGarmentAutoReequip, restores the everyday state once no living
-- boss is targeted. PickupInventoryItem/PutItemInBackpack/EquipItemByName
-- are #nocombat-only on this client (no hardware-event protection), so all
-- of this is legal out of combat; IN combat equipment is locked entirely,
-- which is why the red shirt-gate warning (Modules/Warnings.lua) survives as
-- the fallback there. What was changed is remembered in db.char.garmentFlip
-- (with its direction) so a /reload between attempts doesn't strand it.
-- ---------------------------------------------------------------------------

-- Single idempotent dispatcher; safe to call from any event or timer.
function WeaveBind:GarmentFlipCheck()
  local p = Nock.db and Nock.db.profile
  if not (p and p.weaveBindGarmentAutoFlip and featureActive()
          and macrosTouchGarment()) then
    return
  end
  if InCombatLockdown() then return end
  local memo = Nock.db.char.garmentFlip
  -- The ARM is raid-gated; the everyday-state side backs off for ANY live
  -- boss (worldboss/?? anywhere), so a manually-armed gate at an outdoor
  -- boss (Kazzak/Doomwalker) isn't fought.
  local bossAnywhere = isBossTarget()
  local bossInRaid   = bossAnywhere and Nock.IsInRaidInstance()
  if bossInRaid and not memo then
    -- Respect a deliberate manual reversal: don't fight the user while the
    -- same boss stays targeted (latch set in OnEquipmentChanged).
    if self._overrideGUID and UnitGUID("target") == self._overrideGUID then return end
    self:ArmGarmentGate()
  elseif not bossAnywhere and p.weaveBindGarmentAutoReequip then
    if memo then
      self:DisarmGarmentGate()
    else
      self:EnsureEverydayState()
    end
  end
end

-- Takes the item in `slot` off, into the first regular bag with room.
-- Returns itemID, link on success. On failure returns nil after setting the
-- blocked flag — which un-suppresses the red warning — and leans on the 5s
-- watchdog to retry; the bags-full case explains itself once.
function WeaveBind:StowEquippedItem(slot, garmentName)
  local w = Nock.state.weave
  -- Never disturb something the user is dragging.
  if GetCursorInfo and GetCursorInfo() then
    w.garmentFlipBlocked = true
    return nil
  end
  -- Find bag space BEFORE picking the item up, so the cursor never ends up
  -- holding a garment with nowhere to put it. Nonzero-family bags (quiver /
  -- ammo pouch) can't take a garment.
  local targetBag
  for bag = 0, 4 do
    local free, family = containerFreeSlots(bag)
    if (free or 0) > 0 and (family or 0) == 0 then
      targetBag = bag
      break
    end
  end
  local link = GetInventoryItemLink and GetInventoryItemLink("player", slot)
  if not targetBag then
    w.garmentFlipBlocked = true
    if not self._bagFullWarned then
      self._bagFullWarned = true
      self:Print(("Bags are full — couldn't take %s off; make room or remove it yourself."):format(link or ("your " .. garmentName)))
    end
    return nil
  end
  local itemID = GetInventoryItemID and GetInventoryItemID("player", slot)
  ClearCursor()
  PickupInventoryItem(slot)
  if not (CursorHasItem and CursorHasItem()) then
    w.garmentFlipBlocked = true
    return nil
  end
  putCursorItemInBag(targetBag)
  if CursorHasItem and CursorHasItem() then
    -- The put failed; back onto the body rather than left on the cursor.
    PickupInventoryItem(slot)
    ClearCursor()
    w.garmentFlipBlocked = true
    self:Print(("Couldn't stow %s in a bag — remove it yourself."):format(link or ("your " .. garmentName)))
    return nil
  end
  return itemID, link
end

-- Boss targeted: put the garment into the state that makes the gated lines
-- fire — OFF for the [noequipped:...] direction, ON for [equipped:...].
function WeaveBind:ArmGarmentGate()
  local w = Nock.state.weave
  local g, dir = gateGarment()
  if not g then return end
  if dir == "off" then
    local slot = garmentEquipped(g)
    if not slot then return end  -- already in boss state
    local itemID, link = self:StowEquippedItem(slot, g)
    if not itemID then return end  -- blocked; StowEquippedItem said why
    Nock.db.char.garmentFlip = { itemID = itemID, link = link, slot = slot, garment = g, dir = dir }
    w.garmentFlipBlocked = false
    self._bagFullWarned = nil
    self:Print(("Boss targeted — took %s off: your boss-only macro lines are now active."):format(link or ("your " .. g)))
  else
    -- [equipped:...] direction: the garment must be WORN on the boss.
    if garmentEquipped(g) then return end  -- already in boss state
    local itemID, link = findGarmentInBags(g)
    if not itemID then
      w.garmentFlipBlocked = true
      if not self._noGarmentWarned then
        self._noGarmentWarned = true
        self:Print(("No %s in your bags — put one on yourself to activate the boss-only macro lines."):format(g))
      end
      return
    end
    if not equipItemByID(itemID) then
      w.garmentFlipBlocked = true
      return
    end
    Nock.db.char.garmentFlip = { itemID = itemID, link = link, slot = GARMENT_SLOT[g], garment = g, dir = dir }
    w.garmentFlipBlocked = false
    self._noGarmentWarned = nil
    self:Print(("Boss targeted — put %s on: your boss-only macro lines are now active."):format(link or ("your " .. g)))
  end
  -- Either way, the resulting PLAYER_EQUIPMENT_CHANGED re-resolves the macro
  -- lines via OnEquipmentChanged -> ApplyBind; nothing more to do here.
end

-- No living boss targeted anymore: return the garment to its everyday
-- state, switching the boss-only lines back off.
function WeaveBind:DisarmGarmentGate()
  local memo = Nock.db.char.garmentFlip
  if not memo then return end
  if (memo.dir or "off") == "off" then
    if garmentEquipped(memo.garment) then
      -- Already back on: the user beat us to it, or the memo is stale from
      -- before a /reload. Either way, done.
      Nock.db.char.garmentFlip = false
      return
    end
    if GetItemCount and (GetItemCount(memo.itemID) or 0) == 0 then
      -- Banked/destroyed since removal; retrying forever would spam.
      self:Print(("Couldn't find %s in your bags — put it back on yourself."):format(memo.link or ("your " .. memo.garment)))
      Nock.db.char.garmentFlip = false
      return
    end
    -- Clear the memo BEFORE equipping: OnEquipmentChanged reads a garment
    -- change arriving while the memo exists as the USER's doing.
    Nock.db.char.garmentFlip = false
    if equipItemByID(memo.itemID) then
      self:Print(("Fight over — %s is back on; boss-only macro lines are off again."):format(memo.link or ("your " .. memo.garment)))
    else
      self:Print(("No equip API on this client — put %s back on yourself."):format(memo.link or ("your " .. memo.garment)))
    end
  else
    -- "on" direction: we equipped it for the boss; take it off again.
    local slot = garmentEquipped(memo.garment)
    if not slot then
      Nock.db.char.garmentFlip = false  -- user beat us to it
      return
    end
    -- Clear first for the same reason as above, restore on failure so the
    -- watchdog retries. Safe: equipment events only run after this function
    -- returns, so a failed attempt never masquerades as a user change.
    Nock.db.char.garmentFlip = false
    local itemID, link = self:StowEquippedItem(slot, memo.garment)
    if not itemID then
      Nock.db.char.garmentFlip = memo
      return
    end
    self:Print(("Fight over — %s removed; boss-only macro lines are off again."):format(link or memo.link or ("your " .. memo.garment)))
  end
end

-- With no change of our own pending, keep the gate in its EVERYDAY state
-- whenever no living boss is targeted — anywhere, not just in raids — so a
-- garment left in its boss state (forgotten after a manual swap, a wipe
-- before this feature was on, ...) can't silently burn gated consumables
-- out in the world. Direction-aware: everyday = worn for [noequipped:...]
-- macros, bare for [equipped:...] ones. The _everydayTried latch keeps a
-- failing equip from re-announcing on every watchdog tick.
function WeaveBind:EnsureEverydayState()
  local g, dir = gateGarment()
  if not g then return end
  if dir == "off" then
    if garmentEquipped(g) then
      self._everydayTried = nil
      return
    end
    local itemID, link = findGarmentInBags(g)
    if not itemID then
      if not self._noEverydayWarned then
        self._noEverydayWarned = true
        self:Print(("No %s worn or in your bags — your boss-only macro lines are LIVE and will burn consumables."):format(g))
      end
      return
    end
    self._noEverydayWarned = nil
    local announce = self._everydayTried ~= itemID
    self._everydayTried = itemID
    if equipItemByID(itemID) and announce then
      self:Print(("Put %s on — boss-only macro lines are off (no boss targeted)."):format(link or ("your " .. g)))
    end
  else
    local slot = garmentEquipped(g)
    if not slot then return end
    local itemID, link = self:StowEquippedItem(slot, g)
    if itemID then
      self:Print(("Took %s off — boss-only macro lines are off (no boss targeted)."):format(link or ("your " .. g)))
    end
  end
end

--------------------------------------------------------------------------------
-- Grounded (Gello): import the weave bind (2026-08-27, user).
--------------------------------------------------------------------------------
-- Grounded keeps its binds in the per-character SV GroundedSavedBinds as
-- {name, key, icon, down, up} and binds each with a priority override on a
-- GroundedSecureButton<n>. Nock reads that table -- it exists only while
-- Grounded is enabled and loaded -- finds the bind whose press body is a
-- weave (Raptor Strike or /startattack) and MOVES it: the key and both bodies
-- into the profile, the bind out of Grounded's table, and
-- GroundedFrame:UpdateSecureButtons() so the key is Nock's at once (Grounded
-- clears every override it holds and rebinds what is left; no reload). A
-- copy stays in the profile (weaveBindImported) so UndoGroundedImport can
-- put it back while Grounded is still loaded. Why move rather than bridge:
-- the coach, the live weave log, the practice paper choice and the stage's
-- `w` key all hang off Nock's button edges, and Grounded flips the global
-- ActionButtonUseKeyDown CVar per click where Nock's button sets its own
-- attribute -- one mechanism, in practice and in the raid. Never in combat.
local function groundedWeaveIndex()
  local binds = _G.GroundedSavedBinds
  if type(binds) ~= "table" then return nil end
  local raptor = spellNameOf(C.SpellID.RAPTOR_STRIKE)
  raptor = raptor and raptor:lower()
  for i = 1, #binds do
    local b = binds[i]
    if type(b) == "table" and type(b[2]) == "string" and b[2] ~= "" then
      local down = (b[4] or ""):lower()
      if down:find("/startattack", 1, true) or (raptor and down:find(raptor, 1, true)) then
        return i, b
      end
    end
  end
  return nil
end

function WeaveBind:GroundedLoaded() return type(_G.GroundedSavedBinds) == "table" end

-- The bind Grounded holds, or nil: index, key (as Grounded spells it:
-- ALT-CTRL-SHIFT-key, the client's own order), both bodies.
function WeaveBind:GroundedWeaveBind()
  local i, b = groundedWeaveIndex()
  if not i then return nil end
  return { index = i, key = b[2], down = b[4] or "", up = b[5] or "", name = b[1], icon = b[3] }
end

-- How many binds Grounded still holds (nil when it is not loaded): the
-- "Disable Grounded" offer is made only when the weave bind was its last.
function WeaveBind:GroundedBindCount()
  local binds = _G.GroundedSavedBinds
  if type(binds) ~= "table" then return nil end
  return #binds
end

local function groundedRebind()
  local gf = _G.GroundedFrame
  if gf and gf.UpdateSecureButtons then pcall(gf.UpdateSecureButtons, gf) end
end

-- Move Grounded's weave bind into Nock. Returns true when it moved; says
-- why not otherwise.
function WeaveBind:ImportFromGrounded()
  if InCombatLockdown() then
    self:Print("Weave Bind: not in combat -- import from Grounded when the fight is over.")
    return false
  end
  local i, b = groundedWeaveIndex()
  if not i then
    self:Print("Weave Bind: no weave bind found in Grounded (a bind whose press casts Raptor Strike or /startattack).")
    return false
  end
  local p = Nock.db.profile
  local key = b[2]
  local E = Nock.PracticeEngine
  if E and E.NormalizeKey then key = E.NormalizeKey(key) end
  p.weaveBindImported = {
    name = b[1], key = b[2], icon = b[3], down = b[4], up = b[5],
    prevKey = p.weaveBindKey, prevEnabled = p.weaveBindEnabled == true,
    prevDown = p.weaveBindMacroDown, prevUp = p.weaveBindMacroUp,
  }
  p.weaveBindKey       = key
  p.weaveBindMacroDown = b[4] or ""
  p.weaveBindMacroUp   = b[5] or ""
  p.weaveBindEnabled   = true
  table.remove(_G.GroundedSavedBinds, i)
  groundedRebind()                              -- Grounded lets the key go...
  Nock:SendMessage("NOCK_WEAVEBIND_CHANGED")   -- ...and ApplyBind takes it
  self:Print(("Weave Bind: imported your Grounded weave bind (%s) -- key and both macros. Grounded gave the key up; Nock holds it now."):format(key))
  return true
end

-- Put the imported bind back into Grounded and clear Nock's key. Only while
-- Grounded is loaded (its table must be there to take it).
function WeaveBind:UndoGroundedImport()
  if InCombatLockdown() then
    self:Print("Weave Bind: not in combat -- undo the import when the fight is over.")
    return false
  end
  local p = Nock.db.profile
  local imp = p.weaveBindImported
  if not imp then return false end
  if not self:GroundedLoaded() then
    self:Print("Weave Bind: Grounded is not loaded -- enable it and /reload to give the bind back.")
    return false
  end
  table.insert(_G.GroundedSavedBinds, { imp.name, imp.key, imp.icon, imp.down, imp.up })
  p.weaveBindImported = nil
  p.weaveBindKey = imp.prevKey or ""
  p.weaveBindEnabled = imp.prevEnabled or false
  -- The bodies go back to what they were before the import, but only while
  -- they are still the import's (an edit made since is the user's).
  if p.weaveBindMacroDown == (imp.down or "") then p.weaveBindMacroDown = imp.prevDown end
  if p.weaveBindMacroUp == (imp.up or "") then p.weaveBindMacroUp = imp.prevUp end
  Nock:SendMessage("NOCK_WEAVEBIND_CHANGED")   -- ApplyBind clears Nock's override first...
  groundedRebind()                              -- ...then Grounded takes the key back
  self:Print("Weave Bind: gave the weave bind back to Grounded.")
  return true
end

-- Disable the Grounded addon for this character (takes effect at the next
-- /reload). Offered only once it holds nothing; a separate, confirmed step.
function WeaveBind:DisableGrounded()
  local who = UnitName and UnitName("player") or nil
  if C_AddOns and C_AddOns.DisableAddOn then C_AddOns.DisableAddOn("Grounded", who)
  elseif DisableAddOn then DisableAddOn("Grounded", who)
  else self:Print("Weave Bind: cannot disable addons on this client -- use the AddOns list at the character screen."); return false end
  self:Print("Weave Bind: Grounded is disabled for this character; reloading.")
  return true
end

-- MovePad desync watchdog. The pad's buttons are toggling CheckButtons: the
-- press-edge /click starts the backpedal, the release-edge /click stops it —
-- that pairing is the ONLY thing bounding the step (Grounded has no MovePad
-- code at all; verified against Blizzard_MovePad source). A swallowed release
-- edge (death, alt-tab, loading screen mid-hold) leaves the toggle checked:
-- endless backpedal now, and every later press/release pair runs
-- phase-inverted (walking BETWEEN weaves, standing still during them).
-- Movement functions are hardware-protected, so addon code cannot heal this —
-- detect the stuck state and print the fix. Re-syncing takes an ODD number of
-- extra clicks; the weave key itself (a click PAIR) never fixes it.
function WeaveBind:VerifyMovePad()
  local pad = _G.MovePadBackward
  if not (pad and pad.GetChecked and pad:GetChecked()) then
    self._movePadStuck = nil
    return
  end
  if Nock.state.weave.keyHeld then return end
  if self._movePadStuck then return end
  self._movePadStuck = true
  self:Print("Weave Bind: the Movement Pad backward toggle is stuck ON (a release edge was lost) — you'll keep walking backward. Type /click MovePadBackward once (or click the pad's back button) to stop and re-sync.")
end

-- Legacy safety net: restore ActionButtonUseKeyDown=1 when a CVar-flipping
-- macro plausibly left it at 0. The shipped mechanism no longer touches the
-- CVar (the secure wrapper drives the useOnKeyDown attribute instead), so this
-- only ever acts when the stored macro bodies themselves reference the CVar —
-- users who run cast-on-release by deliberate choice are never overridden.
function WeaveBind:VerifyCVar()
  if not macrosTouchCVar() then return end
  if not (featureActive() or self._sawDown) then return end
  if (GetCVar and GetCVar("ActionButtonUseKeyDown") or "1") ~= "0" then return end
  local w = Nock.state.weave
  local heldRecently = w.keyHeld and (GetTime() - (w.keyHeldSince or 0)) < HELD_STALE_SEC
  if heldRecently then return end
  if SetCVar then SetCVar("ActionButtonUseKeyDown", "1") end
  w.keyHeld = false
  if not self._restoreNotified then
    self._restoreNotified = true
    self:Print("Weave Bind: restored cast-on-key-down (ActionButtonUseKeyDown 1) after an interrupted hold.")
  end
end
