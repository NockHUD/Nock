-- Forever/AspectRing.lua
-- The aspect ring: a held key opens the hunter's aspects at the cursor out of combat, casts Hawk in combat.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")

local TWO_PI = 2 * math.pi

-- Pure. The slot under a flick: dx, dy from the ring centre (y up), slot 1
-- straight up and clockwise, each slot owning a 360/n degree wedge centred on
-- its direction. nil inside the cancel circle.
function Nock.AspectRingPick(dx, dy, deadRadius, n)
  n = n or 6
  if type(dx) ~= "number" or type(dy) ~= "number" then return nil end
  if dx * dx + dy * dy < deadRadius * deadRadius then return nil end
  local a = math.atan2(dx, dy)          -- 0 = up, +pi/2 = right (clockwise)
  if a < 0 then a = a + TWO_PI end
  local w = TWO_PI / n
  return (math.floor((a + w / 2) / w) % n) + 1
end

-- Pure. Slot i's centre relative to the ring centre (y up).
function Nock.AspectRingSlotOffset(i, radius, n)
  local a = (i - 1) * TWO_PI / (n or 6)
  return radius * math.sin(a), radius * math.cos(a)
end

-- Pure. The cast line: `!` keeps an aspect that is already up from being
-- toggled off.
function Nock.AspectRingMacro(name)
  if type(name) ~= "string" or name == "" then return nil end
  return "/cast !" .. name
end

-- Pure. The ring's name label: every aspect's name minus the prefix they all
-- share, cut back to a word ("Aspect of the Cheetah" -> "Cheetah"; German
-- "Aspekt des Falken" -> "des Falken"). Learned from the names themselves,
-- so no locale is written into the code. `names` is indexed 1..6 and may
-- have holes; fewer than two names leave them whole.
function Nock.AspectRingShortNames(names)
  local list = {}
  for i = 1, 6 do if type(names[i]) == "string" then list[#list + 1] = names[i] end end
  local prefix = ""
  if #list >= 2 then
    prefix = list[1]
    for k = 2, #list do
      local s, n = list[k], 0
      while n < #prefix and n < #s and prefix:sub(n + 1, n + 1) == s:sub(n + 1, n + 1) do n = n + 1 end
      prefix = prefix:sub(1, n)
    end
    prefix = prefix:match("^(.*%s)") or ""
  end
  local out = {}
  for i = 1, 6 do
    local n = names[i]
    if type(n) == "string" then out[i] = n:sub(#prefix + 1) end
  end
  return out
end

-- Pure. The dial layout from the profile (aspectRingOrder, a list of aspect
-- keys by direction, clockwise from up): unknown keys and repeats dropped,
-- the missing appended in default order, so every aspect sits exactly once.
-- Always a fresh table; nil or junk is the default layout.
function Nock.AspectRingOrder(stored)
  local def = Nock.Spells.ASPECT_RING
  local valid = {}
  for _, k in ipairs(def) do valid[k] = true end
  local out, seen = {}, {}
  if type(stored) == "table" then
    for i = 1, #def do
      local k = stored[i]
      if valid[k] and not seen[k] then out[#out + 1] = k; seen[k] = true end
    end
  end
  for _, k in ipairs(def) do
    if not seen[k] then out[#out + 1] = k; seen[k] = true end
  end
  return out
end

-- Pure. `key` placed at direction `dir`; the aspect that was there takes
-- key's old direction (a swap). An unknown key changes nothing.
function Nock.AspectRingSwap(order, dir, key)
  local from
  for i, k in ipairs(order) do if k == key then from = i end end
  if not from or not order[dir] then return order end
  order[from], order[dir] = order[dir], key
  return order
end

-- key ("hawk") -> base spell id, from Nock.Spells.ASPECTS (id -> key).
function Nock.AspectRingIdByKey()
  local out = {}
  for id, key in pairs(Nock.Spells.ASPECTS) do out[key] = id end
  return out
end

-- Geometry shared with the view (UI/Frame_AspectRing.lua): the cancel circle
-- and the ring's radius, in UIParent units (~90 across).
local DEAD_RADIUS, RING_RADIUS = 14, 45
function Nock.AspectRingGeometry() return DEAD_RADIUS, RING_RADIUS end

-- Ring size (Utilities -> Aspect ring): 75..200 %, 100 % when unset. The
-- view scales the whole layer; the cancel circle scales with it here.
function Nock.AspectRingScale(p)
  local v = p and tonumber(p.aspectRingScale) or 1
  if v < 0.75 then v = 0.75 elseif v > 2 then v = 2 end
  return v
end

-- The Key Bindings entry is Bindings.xml; its label is in Core/Bindings.lua.

local AspectRing = Nock:NewModule("AspectRing", "AceEvent-3.0")
-- No refreshInterval: while open the ring follows the cursor every frame.

local ID_BY_KEY

local function nameOf(id)
  local n = Nock.Flavor.Plain(Nock.API.SpellName(id))
  if type(n) == "string" then return n end
  return nil
end

function AspectRing:OnEnable()
  ID_BY_KEY = Nock.AspectRingIdByKey()
  -- A plain secure button the binding clicks (no snippets: they are dead on
  -- this beta). Both edges arrive; PreClick (insecure) decides out of combat.
  -- RegisterForClicks waits for the first arming: under a combat /reload the
  -- lockdown forbids it, and the key does nothing until combat ends anyway.
  local b = CreateFrame("Button", "NockAspectRingButton", UIParent, "SecureActionButtonTemplate")
  b:SetScript("PreClick", function(_, _, down) self:OnKey(down) end)
  self.button = b
  self:RegisterEvent("PLAYER_REGEN_DISABLED")
  self:RegisterEvent("PLAYER_REGEN_ENABLED")
  self:RegisterEvent("SPELLS_CHANGED", "UpdateKnown")
  self:RegisterMessage("NOCK_ASPECT_RING_CLOSE", "Close")
  -- The settings page (the key, the dial) and a profile switch.
  self:RegisterMessage("NOCK_ASPECT_RING_CONFIG", "OnConfig")
  self:RegisterMessage("NOCK_VISUALS_CHANGED", "OnConfig")
  self:UpdateKnown()
  if not InCombatLockdown() then self:ArmRing() end
  self:ApplyBinding()
end

function AspectRing:OnConfig()
  self:UpdateKnown()
  self:ApplyBinding()
end

local function profile()
  return (Nock.db and Nock.db.profile) or {}
end

-- The key from Nock's settings (aspectRingKey): a priority override on the
-- key button, like the weave key. Binding calls are protected in combat, so
-- a change made there lands when combat ends.
function AspectRing:ApplyBinding()
  if InCombatLockdown() then self._bindPending = true; return end
  self._bindPending = nil
  local b = self.button
  if not b then return end
  ClearOverrideBindings(b)
  local key = profile().aspectRingKey
  if type(key) == "string" and key ~= "" then
    SetOverrideBindingClick(b, true, key, "NockAspectRingButton")
  end
end

-- Ring mode: nothing armed, and the release edge is the one that casts
-- (PreClick sets the aspect on that same edge).
-- Both edges must reach the button; set once, out of combat (see OnEnable).
local function takeClicks(b)
  if b._nockClicks then return end
  b:RegisterForClicks("AnyDown", "AnyUp")
  b._nockClicks = true
end

function AspectRing:ArmRing()
  local b = self.button
  takeClicks(b)
  b:SetAttribute("useOnKeyDown", false)
  b:SetAttribute("type", nil)
  b:SetAttribute("macrotext", nil)
end

-- Combat mode: Hawk, on whichever edge the client's key-down option says
-- (nil = follow the cvar, like the action bars). Nothing when Hawk is not
-- learned. Runs in PLAYER_REGEN_DISABLED, before the lockdown.
function AspectRing:ArmHawk()
  local b = self.button
  takeClicks(b)
  local st = Nock.state.aspectRing
  local slot
  for i, key in ipairs(st.order) do if key == "hawk" then slot = i end end
  local macro = Nock.AspectRingMacro(slot and st.known[slot])
  b:SetAttribute("useOnKeyDown", nil)
  if macro then
    b:SetAttribute("type", "macro")
    b:SetAttribute("macrotext", macro)
  else
    b:SetAttribute("type", nil)
    b:SetAttribute("macrotext", nil)
  end
end

function AspectRing:PLAYER_REGEN_DISABLED()
  self:Close()
  self:ArmHawk()
end

function AspectRing:PLAYER_REGEN_ENABLED()
  self:ArmRing()
  if self._bindPending then self:ApplyBinding() end
end

-- The key's two edges, out of combat only (in combat the attributes are
-- fixed and this must not touch them).
function AspectRing:OnKey(down)
  if InCombatLockdown() then return end
  local b = self.button
  if down then
    b:SetAttribute("type", nil)
    b:SetAttribute("macrotext", nil)
    self:Open()
    return
  end
  local st = Nock.state.aspectRing
  local name
  if st.open then
    self:UpdateHover()
    name = st.hover and st.known[st.hover] or nil
  end
  local macro = Nock.AspectRingMacro(name)
  if macro then
    b:SetAttribute("type", "macro")
    b:SetAttribute("macrotext", macro)
  else
    b:SetAttribute("type", nil)
    b:SetAttribute("macrotext", nil)
  end
  self:Close()
end

local function cursor()
  local x, y = GetCursorPosition()
  local s = UIParent:GetEffectiveScale()
  return x / s, y / s
end

function AspectRing:Open()
  local st = Nock.state.aspectRing
  st.cx, st.cy = cursor()
  st.hover = nil
  st.open = true
end

function AspectRing:Close()
  local st = Nock.state.aspectRing
  st.open = false
  st.hover = nil
end

-- The slot under the flick; an unlearned slot is no slot.
function AspectRing:UpdateHover()
  local st = Nock.state.aspectRing
  local x, y = cursor()
  local i = Nock.AspectRingPick(x - st.cx, y - st.cy, DEAD_RADIUS * Nock.AspectRingScale(profile()))
  if i and not st.known[i] then i = nil end
  st.hover = i
end

-- Learned aspects by NAME (ranks are separate spells on Forever), slot by
-- slot in the dial layout from the profile. Without the spellbook API every
-- slot is offered.
function AspectRing:UpdateKnown()
  if not ID_BY_KEY then ID_BY_KEY = Nock.AspectRingIdByKey() end
  local st = Nock.state.aspectRing
  local order = Nock.AspectRingOrder(profile().aspectRingOrder)
  local names = Nock.ForeverSpellbookNames()
  local changed = false
  local all = {}
  for i, key in ipairs(order) do
    if st.order[i] ~= key then changed = true end
    local n = nameOf(ID_BY_KEY[key])
    all[i] = n
    local v = nil
    if n and (names == nil or names[n]) then v = n end
    if st.known[i] ~= v then st.known[i] = v; changed = true end
  end
  st.order = order
  if changed then st.knownRev = st.knownRev + 1 end
  -- The label names, from all six (learned or not) so the shared prefix is
  -- the same whatever the character knows.
  st.short = Nock.AspectRingShortNames(all)
end

function AspectRing:Refresh(state)
  if state.aspectRing.open then self:UpdateHover() end
end
