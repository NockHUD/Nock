-- Modules/BindCheck.lua
-- Resolves what ELSE is bound to the keys Nock claims, into state.binds.
--
-- Modules/WeaveBind.lua claims its key with
-- SetOverrideBindingClick(button, true, key, name) -- priority = true. That means
-- Nock ALWAYS wins the key: the user's own binding is not overwritten, it is
-- silently suppressed for as long as the feature is on, and comes back when it is
-- turned off. Nothing told the user that happened, so a key that used to cast
-- Multi-Shot simply stopped casting it.
--
-- FEATURES is a list rather than a single entry, and the loop stays generic, but
-- it holds exactly one claimant now. It held two until 1.0.19, when the Steam
-- Tonk hold key was retired -- PetDismiss made an in-combat exit possible, so a
-- human finger no longer had to supply the settling delay. The nock-vs-nock
-- self-conflict branch went with it rather than staying as a branch no test
-- could reach; git has it if a second key ever comes back.
--
-- This module only ever LOOKS. It never sets, clears or suggests a binding --
-- rebinding is the user's business.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local BindCheck = Nock:NewModule("BindCheck", "AceEvent-3.0", "AceTimer-3.0")

-- ACTIONBAR_SLOT_CHANGED arrives once per slot, so a bar swap or a login fires it
-- in bursts. Coalesce into one recompute.
local RECOMPUTE_THROTTLE = 0.2

-- The features that claim a key. `button` is the CLICK target each one binds, so
-- an effective-binding lookup can recognise Nock's own claim.
local FEATURES = {
  { slot = "weave", label = "Weave Bind", keyKey = "weaveBindKey", enabledKey = "weaveBindEnabled",
    button = "NockWeaveBindButton" },
}

-- Blizzard bar binding -> the frame that owns the action slot. Reading `.action`
-- off the live frame is preferred over arithmetic because it already accounts for
-- paging, stances and anything else that repoints a bar.
local BAR_FRAME = {
  ACTIONBUTTON          = "ActionButton",
  MULTIACTIONBAR1BUTTON = "MultiBarBottomLeftButton",
  MULTIACTIONBAR2BUTTON = "MultiBarBottomRightButton",
  MULTIACTIONBAR3BUTTON = "MultiBarRightButton",
  MULTIACTIONBAR4BUTTON = "MultiBarLeftButton",
}

-- Fallback slot arithmetic for when the frame is absent (a bar addon replacing
-- Blizzard's bars). Standard TBC layout: 1-12/13-24 are the main bar's pages,
-- 25-36 Right, 37-48 Right 2, 49-60 Bottom Right, 61-72 Bottom Left.
local BAR_BASE = {
  MULTIACTIONBAR1BUTTON = 60,
  MULTIACTIONBAR2BUTTON = 48,
  MULTIACTIONBAR3BUTTON = 24,
  MULTIACTIONBAR4BUTTON = 36,
}

local function profile()
  return (Nock.db and Nock.db.profile) or {}
end

-- "CLICK DominosActionButton4:HOTKEY" -> "DominosActionButton4". Frame names
-- cannot contain a colon, so the first one always ends the name.
local function clickTarget(action)
  return action and action:match("^CLICK%s+([^:]+)") or nil
end

-- The action slot a frame drives, if any. Bar addons keep it on `.action`
-- (Dominos does); secure buttons keep it in the "action" attribute. A cast-on-
-- keypress helper button inherits its parent's slot ("useparent-action"), so a
-- childless answer falls through to the parent.
local function frameActionSlot(name, depth)
  local f = name and _G[name]
  if type(f) ~= "table" then return nil end
  local slot = tonumber(f.action)
  if not slot and type(f.GetAttribute) == "function" then
    local okAttr, v = pcall(f.GetAttribute, f, "action")
    if okAttr then slot = tonumber(v) end
  end
  if slot then return slot end
  if (depth or 0) < 1 and type(f.GetParent) == "function" then
    local okParent, parent = pcall(f.GetParent, f)
    if okParent and type(parent) == "table" then
      local slotP = tonumber(parent.action)
      if not slotP and type(parent.GetAttribute) == "function" then
        local okAttr, v = pcall(parent.GetAttribute, parent, "action")
        if okAttr then slotP = tonumber(v) end
      end
      return slotP
    end
  end
  return nil
end

-- Action slot behind a binding action string, or nil if it isn't a bar binding.
local function actionSlotFor(action)
  if type(action) ~= "string" or action == "" then return nil end

  local clicked = clickTarget(action)
  if clicked then return frameActionSlot(clicked) end

  -- Non-greedy up to the FIRST "BUTTON" so MULTIACTIONBAR1BUTTON3 splits as
  -- ("MULTIACTIONBAR1BUTTON", "3") rather than swallowing the bar's own digit.
  local prefix, n = action:match("^(.-BUTTON)(%d+)$")
  if not prefix then return nil end
  n = tonumber(n)

  local frame = BAR_FRAME[prefix]
  if frame then
    local slot = frameActionSlot(frame .. n)
    if slot then return slot end
  end

  if prefix == "ACTIONBUTTON" then
    local page = (GetActionBarPage and GetActionBarPage()) or 1
    if page < 1 then page = 1 end
    return (page - 1) * 12 + n
  end
  local base = BAR_BASE[prefix]
  return base and (base + n) or nil
end

local function spellName(id)
  if GetSpellInfo then
    local n = GetSpellInfo(id)
    if n then return n end
  end
  if C_Spell and C_Spell.GetSpellInfo then
    local i = C_Spell.GetSpellInfo(id)
    if i and i.name then return i.name end
  end
  return nil
end

local function itemName(id)
  if GetItemInfo then
    local n = GetItemInfo(id)
    if n then return n end
  end
  if C_Item and C_Item.GetItemInfo then
    local n = C_Item.GetItemInfo(id)
    if n then return n end
  end
  return nil
end

-- What is sitting in an action slot: a display name, or nil when the slot is
-- empty. Macros carry their name as the slot's action text; spells and items
-- resolve by id.
local function slotContents(slot)
  if not slot then return nil end
  if HasAction and not HasAction(slot) then return nil end
  if not GetActionInfo then return nil end
  local kind, id = GetActionInfo(slot)
  if not kind then return nil end
  if kind == "macro" then
    local text = GetActionText and GetActionText(slot)
    return (text and text ~= "" and text) or "a macro"
  elseif kind == "spell" then
    return (id and spellName(id)) or "a spell"
  elseif kind == "item" then
    return (id and itemName(id)) or "an item"
  end
  return kind
end

-- Human name for a plain binding token, localized where the client knows it.
local function bindingLabel(action)
  return _G["BINDING_NAME_" .. action] or action
end

-- Classify one key. Returns nil when the key is free, else a conflict record.
local function classify(feature)
  local p = profile()
  local key = p[feature.keyKey]
  if type(key) ~= "string" or key == "" then return nil end

  local action = (GetBindingAction and GetBindingAction(key)) or ""
  if action == "" then return nil end

  -- Nock's own click target showing up as a BASE binding would mean the user
  -- hand-bound our button in the keybinding UI. Nothing to warn about.
  local clicked = clickTarget(action)
  if clicked == feature.button then return nil end

  local slot = actionSlotFor(action)
  if slot then
    local contents = slotContents(slot)
    return {
      kind   = "action",
      action = action,
      slot   = slot,
      label  = contents or bindingLabel(action),
      empty  = contents == nil,
    }
  end

  if clicked then
    return { kind = "click", action = action, label = clicked }
  end
  return { kind = "binding", action = action, label = bindingLabel(action) }
end

-- Does Nock currently hold the key? Only ever answered in the POSITIVE: the
-- checkOverride argument to GetBindingAction is not on this client's verified
-- allowlist, and a client that ignores it returns the base binding instead --
-- which must not be read as "another addon stole the key".
local function ownedByNock(feature, key)
  if not (key and key ~= "" and GetBindingAction) then return false end
  local effective = GetBindingAction(key, true)
  return clickTarget(effective) == feature.button
end

function BindCheck:Recompute()
  local p = profile()
  for _, feature in ipairs(FEATURES) do
    local s = Nock.state.binds[feature.slot]
    -- The feature's own name, published so views never hardcode "Weave".
    -- It doubles as the answer to "where do I go to fix this": it is exactly the
    -- Settings page title (Utilities -> Weave Bind).
    s.label       = feature.label
    s.key         = p[feature.keyKey] or ""
    s.enabled     = p[feature.enabledKey] == true
    s.conflict    = classify(feature)
    s.ownedByNock = ownedByNock(feature, s.key)
  end
end

-- Does this rise to an on-screen warning? Only when the key is actually claimed
-- (the feature is enabled) AND something is genuinely lost. A key bound to an
-- action-bar slot that is EMPTY costs nothing — a real case: a Dominos button
-- with no spell on it — so it must never raise a square. The Settings note and
-- /nock binds still report it; the alert stack stays for things worth reacting
-- to. This is the one definition of "worth warning about"; views call it rather
-- than re-deriving the rule.
function BindCheck:ShouldWarn(which)
  local s = Nock.state.binds[which]
  if not (s and s.enabled and s.conflict) then return false end
  if s.conflict.empty then return false end
  return true
end

-- One sentence describing the state of a feature's key, or nil when there is
-- nothing to say. The single source of this phrasing: the Settings note and the
-- chat line printed when a key is picked both read it, so they can never drift.
function BindCheck:Note(which)
  local s = Nock.state.binds[which]
  if not s or not s.conflict then return nil end
  local c = s.conflict
  if c.kind == "action" and c.empty then
    return ("that key is bound to %s, but the slot is empty — nothing to lose")
      :format(c.action or c.label)
  elseif c.kind == "action" then
    return ("that key currently uses %s — it will stop doing that while this is on"):format(c.label)
  elseif c.kind == "click" then
    return ("that key is already bound to another addon's button (%s)"):format(c.label)
  end
  return ("that key is already bound to %s"):format(c.label)
end

-- /nock binds — what each key resolves to and who currently owns it. The
-- ownership line is the one that answers "is the bind actually working": it is
-- only ever printed as a positive, for the reason given above ownedByNock.
function BindCheck:Dump()
  self:Recompute()
  for _, feature in ipairs(FEATURES) do
    local s = Nock.state.binds[feature.slot]
    Nock:Print(("%s: key=%s enabled=%s%s"):format(
      feature.label,
      (s.key ~= "" and s.key) or "(none set)",
      tostring(s.enabled),
      s.ownedByNock and " |cff20c020(Nock owns this key)|r" or ""))
    if s.key ~= "" then
      local action = (GetBindingAction and GetBindingAction(s.key)) or ""
      Nock:Print(("  base binding: %s | action slot: %s"):format(
        (action ~= "" and action) or "(free)",
        tostring(s.conflict and s.conflict.slot)))
      Nock:Print(("  verdict: %s"):format(self:Note(feature.slot) or "no conflict"))
    end
  end
end

-- Coalesced recompute. ACTIONBAR_SLOT_CHANGED in particular arrives once per
-- slot, so the naive version would resolve every binding a dozen times a login.
function BindCheck:Queue()
  if self._queued then return end
  self._queued = true
  self:ScheduleTimer(function()
    self._queued = false
    self:Recompute()
  end, RECOMPUTE_THROTTLE)
end

function BindCheck:OnEnable()
  self:RegisterEvent("UPDATE_BINDINGS",         "Queue")
  self:RegisterEvent("ACTIONBAR_SLOT_CHANGED",  "Queue")
  self:RegisterEvent("ACTIONBAR_PAGE_CHANGED",  "Queue")
  self:RegisterEvent("PLAYER_ENTERING_WORLD",   "Queue")
  -- Bindings can only be applied out of combat, so the picture can change the
  -- moment a fight ends.
  self:RegisterEvent("PLAYER_REGEN_ENABLED",    "Queue")
  self:RegisterMessage("NOCK_WEAVEBIND_CHANGED", "Queue")
  self:RegisterMessage("NOCK_VISUALS_CHANGED",   "Queue")
  self:Recompute()
end
