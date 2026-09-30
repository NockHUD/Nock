-- Forever/AspectRing.lua
-- The aspect ring: a held key opens the hunter's aspects at the cursor; a flick and release casts one, in or out of combat.

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

-- Pure. The same pick the secure snippet makes: the slot whose direction is
-- nearest the flick (largest dot product with its unit vector), which is
-- exactly AspectRingPick's wedges; no atan2, which the restricted
-- environment may not offer. Tested against AspectRingPick.
function Nock.AspectRingDirs(n)
  n = n or 6
  local out = {}
  for i = 1, n do
    local a = (i - 1) * TWO_PI / n
    out[i] = { math.sin(a), math.cos(a) }
  end
  return out
end

function Nock.AspectRingPickDot(dx, dy, deadRadius, n)
  if type(dx) ~= "number" or type(dy) ~= "number" then return nil end
  if dx * dx + dy * dy < deadRadius * deadRadius then return nil end
  local best, bi
  for i, d in ipairs(Nock.AspectRingDirs(n)) do
    local v = dx * d[1] + dy * d[2]
    if not best or v >= best then best, bi = v, i end   -- a tie (a wedge edge) goes clockwise, as in AspectRingPick
  end
  return bi
end

-- The key button's wrapped OnClick (secure, so it runs in combat too; snippets
-- work on Forever since the client fix, probed 2026-09-26). `control` is the
-- full-screen header, so GetMousePosition is the cursor's screen fraction.
-- Down: remember the cursor, show the drawn ring there (a protected frame,
-- so only a snippet may move it in combat), arm nothing. Up: hide it; a flick
-- past the cancel circle casts that slot's aspect on this release, otherwise
-- nothing. The attributes (aspect1..6, dead, scale, sw, sh) and the `layer`
-- frame ref are written out of combat.
function Nock.AspectRingSnippet(n, prefix)
  prefix = prefix or "aspect"
  local lines = {
    "local x, y = control:GetMousePosition()",
    "local layer = self:GetFrameRef('layer')",
    "self:SetAttribute('type', nil)",
    "self:SetAttribute('useOnKeyDown', false)",
    "if down then",
    "  self:SetAttribute('ringX', x); self:SetAttribute('ringY', y)",
    "  if layer and x then",
    "    local sc = self:GetAttribute('scale') or 1",
    "    layer:ClearAllPoints()",
    "    layer:SetPoint('CENTER', control, 'BOTTOMLEFT', x * (self:GetAttribute('sw') or 0) / sc, y * (self:GetAttribute('sh') or 0) / sc)",
    "    layer:Show()",
    "  end",
    "  return false",
    "end",
    "if layer then layer:Hide() end",
    "local cx, cy = self:GetAttribute('ringX'), self:GetAttribute('ringY')",
    "self:SetAttribute('ringX', nil); self:SetAttribute('ringY', nil)",
    "if not (x and cx) then return false end",
    "local dx = (x - cx) * (self:GetAttribute('sw') or 0)",
    "local dy = (y - cy) * (self:GetAttribute('sh') or 0)",
    "local dead = self:GetAttribute('dead') or 14",
    "if dx * dx + dy * dy < dead * dead then return false end",
    "local best, bi",
  }
  for i, d in ipairs(Nock.AspectRingDirs(n)) do
    lines[#lines + 1] = ("do local v = dx * %.7f + dy * %.7f if not best or v >= best then best, bi = v, %d end end"):format(d[1], d[2], i)
  end
  lines[#lines + 1] = "local name = bi and self:GetAttribute('" .. prefix .. "' .. bi)"
  lines[#lines + 1] = "if not name then return false end"
  lines[#lines + 1] = "self:SetAttribute('type', 'macro')"
  lines[#lines + 1] = "self:SetAttribute('macrotext', '/cast !' .. name)"
  return table.concat(lines, "\n")
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
-- so no locale is written into the code. `names` is indexed 1..n (6 unless
-- given) and may have holes; fewer than two names leave them whole.
function Nock.AspectRingShortNames(names, n)
  n = n or 6
  local list = {}
  for i = 1, n do if type(names[i]) == "string" then list[#list + 1] = names[i] end end
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
  for i = 1, n do
    local nm = names[i]
    if type(nm) == "string" then out[i] = nm:sub(#prefix + 1) end
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

-- Geometry shared with the view (UI/Frame_AspectRing.lua), in UIParent
-- units: the cancel circle, the ring's radius (the tile centres) and the
-- disc's size, for `n` slots (6 unless given). The radius keeps neighbouring
-- tile centres SLOT_PITCH apart, so six slots sit at 45 on a 150 disc and
-- eight at 59 on a 178 one (at 45 eight 36 tiles overlapped by 4). The pick
-- is by angle, so a wider ring is no longer a flick.
local DEAD_RADIUS = 14
local SLOT_PITCH = 45    -- a 36 tile and the 9 between two of the six
local DISC_MARGIN = 30   -- the disc's rim beyond the tile centres
function Nock.AspectRingGeometry(n)
  local radius = math.floor(SLOT_PITCH / (2 * math.sin(math.pi / (n or 6))) + 0.5)
  return DEAD_RADIUS, radius, 2 * (radius + DISC_MARGIN)
end

-- Ring size (Utilities -> Aspect ring / Tracking wheel): 75..200 %, 100 %
-- when unset. The view scales the whole layer; the cancel circle scales
-- with it here. `key` is the profile key (aspectRingScale unless given).
function Nock.RingScale(p, key)
  local v = p and tonumber(p[key or "aspectRingScale"]) or 1
  if v < 0.75 then v = 0.75 elseif v > 2 then v = 2 end
  return v
end
function Nock.AspectRingScale(p) return Nock.RingScale(p, "aspectRingScale") end

-- The Key Bindings entries are Bindings.xml; their labels are in Core/Bindings.lua.

-- The ring module factory: the aspect ring and the tracking wheel
-- (Forever/TrackingWheel.lua) are the same mechanism under different names.
-- `spec`:
--   name          the module name ("AspectRing")
--   button/screen/layer   the global frame names (the layer is the view's)
--   stateKey      the Nock.state slot ("aspectRing")
--   n             slots
--   prefix        the snippet's per-slot attribute name ("aspect" -> aspect1..n)
--   keyProfile / scaleProfile   the profile keys for the held key and the size
--   configMsg / closeMsg        the messages the settings page and the view send
--   idByKey()     slot key -> spell id
--   order(p)      the slot keys by direction from the profile
--   manaTint      publish noMana per slot (the aspect ring; tracking is free)
function Nock.NewRingModule(spec)
  local Ring = Nock:NewModule(spec.name, "AceEvent-3.0")
  -- No refreshInterval: while open the ring follows the cursor every frame.
  Ring.spec = spec

  local ID_BY_KEY
  local n = spec.n

  local function nameOf(id)
    local nm = Nock.Flavor.Plain(Nock.API.SpellName(id))
    if type(nm) == "string" then return nm end
    return nil
  end

  local function profile()
    return (Nock.db and Nock.db.profile) or {}
  end

  local function state() return Nock.state[spec.stateKey] end

  function Ring:OnEnable()
    ID_BY_KEY = spec.idByKey()
    -- The key's secure button. Picking is a wrapped OnClick snippet (secure:
    -- works in combat); PreClick (insecure) only opens and closes the drawn
    -- ring, which the client allows in combat. Everything secure is built and
    -- written out of combat: under a combat /reload it waits for the end.
    local b = CreateFrame("Button", spec.button, UIParent, "SecureActionButtonTemplate")
    b:SetScript("PreClick", function(_, _, down) self:OnKey(down) end)
    self.button = b
    self:RegisterEvent("PLAYER_REGEN_ENABLED")
    self:RegisterEvent("SPELLS_CHANGED", "UpdateKnown")
    -- AceEvent hard-errors on an event the client lacks
    if spec.manaTint then pcall(self.RegisterEvent, self, "SPELL_UPDATE_USABLE", "ScanUsable") end
    pcall(self.RegisterEvent, self, "UI_SCALE_CHANGED", "PushSecure")
    pcall(self.RegisterEvent, self, "DISPLAY_SIZE_CHANGED", "PushSecure")
    self:RegisterMessage(spec.closeMsg, "Close")
    -- The settings page (the key, the dial, the size) and a profile switch.
    self:RegisterMessage(spec.configMsg, "OnConfig")
    self:RegisterMessage("NOCK_VISUALS_CHANGED", "OnConfig")
    self:UpdateKnown()
    if not InCombatLockdown() then self:Arm() end
    self:ApplyBinding()
  end

  function Ring:OnConfig()
    self:UpdateKnown()
    self:PushSecure()
    self:ApplyBinding()
  end

  -- The key from Nock's settings: a priority override on the key button,
  -- like the weave key. Binding calls are protected in combat, so a change
  -- made there lands when combat ends.
  function Ring:ApplyBinding()
    if InCombatLockdown() then self._bindPending = true; return end
    self._bindPending = nil
    local b = self.button
    if not b then return end
    ClearOverrideBindings(b)
    local key = profile()[spec.keyProfile]
    if type(key) == "string" and key ~= "" then
      SetOverrideBindingClick(b, true, key, spec.button)
    end
  end

  -- Once, out of combat: both edges to the button, the full-screen header the
  -- snippet reads the cursor through, the wrapped OnClick. A secure header
  -- built under lockdown comes out unprotected (probed 2026-09-26), hence the
  -- wait for PLAYER_REGEN_ENABLED after a combat /reload.
  function Ring:Arm()
    if self._armed or InCombatLockdown() then return end
    local b = self.button
    b:RegisterForClicks("AnyDown", "AnyUp")
    b:SetAttribute("useOnKeyDown", false)
    b:SetAttribute("type", nil)
    b:SetAttribute("macrotext", nil)
    local h = CreateFrame("Frame", spec.screen, UIParent, "SecureHandlerBaseTemplate")
    h:SetAllPoints(UIParent)
    self.screen = h
    -- the drawn ring (the view builds it in OnInitialize)
    if _G[spec.layer] then SecureHandlerSetFrameRef(b, "layer", _G[spec.layer]) end
    SecureHandlerWrapScript(b, "OnClick", h, Nock.AspectRingSnippet(n, spec.prefix))
    self._armed = true
    self:PushSecure()
  end

  -- What the snippet reads: the dial's learned names, the cancel radius (Ring
  -- size) and the screen size in UIParent units. Out of combat only; a change
  -- made in combat (a spell learned, the dial, the size) lands when it ends.
  function Ring:PushSecure()
    if not self._armed then return end
    if InCombatLockdown() then self._pushPending = true; return end
    self._pushPending = nil
    local b, st = self.button, state()
    for i = 1, n do b:SetAttribute(spec.prefix .. i, st.known[i]) end
    b:SetAttribute("dead", DEAD_RADIUS * Nock.RingScale(profile(), spec.scaleProfile))
    b:SetAttribute("scale", Nock.RingScale(profile(), spec.scaleProfile))
    self._sw, self._sh = UIParent:GetWidth(), UIParent:GetHeight()
    b:SetAttribute("sw", self._sw)
    b:SetAttribute("sh", self._sh)
  end

  function Ring:PLAYER_REGEN_ENABLED()
    if not self._armed then self:Arm() end
    if self._pushPending then self:PushSecure() end
    if self._bindPending then self:ApplyBinding() end
  end

  -- The key's two edges, drawing only (the pick and the cast are the snippet's):
  -- down opens the ring at the cursor, up closes it. Allowed in combat.
  function Ring:OnKey(down)
    if down then self:Open() else self:Close() end
  end

  local function cursor()
    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    return x / s, y / s
  end

  function Ring:Open()
    local st = state()
    st.cx, st.cy = cursor()
    st.hover = nil
    st.open = true
    self:ScanUsable()
  end

  function Ring:Close()
    local st = state()
    st.open = false
    st.hover = nil
  end

  -- The slot under the flick; an unlearned slot is no slot.
  function Ring:UpdateHover()
    local st = state()
    local x, y = cursor()
    local i = Nock.AspectRingPick(x - st.cx, y - st.cy, DEAD_RADIUS * Nock.RingScale(profile(), spec.scaleProfile), n)
    if i and not st.known[i] then i = nil end
    st.hover = i
  end

  -- Learned spells by NAME (ranks are separate spells on Forever), slot by
  -- slot in the dial layout from the profile. Without the spellbook API every
  -- slot is offered.
  function Ring:UpdateKnown()
    if not ID_BY_KEY then ID_BY_KEY = spec.idByKey() end
    local st = state()
    local order = spec.order(profile())
    local names = Nock.ForeverSpellbookNames()
    local changed = false
    local all = {}
    for i, key in ipairs(order) do
      if st.order[i] ~= key then changed = true end
      local nm = nameOf(ID_BY_KEY[key])
      all[i] = nm
      local v = nil
      if nm and (names == nil or names[nm]) then v = nm end
      if st.known[i] ~= v then st.known[i] = v; changed = true end
      if spec.manaTint then
        local learnedId = names and nm and names[nm]
        st.castId[i] = (type(learnedId) == "number" and learnedId) or ID_BY_KEY[key]
      end
    end
    st.order = order
    if changed then st.knownRev = st.knownRev + 1 end
    -- The label names, from every slot (learned or not) so the shared prefix
    -- is the same whatever the character knows.
    st.short = Nock.AspectRingShortNames(all, n)
    if changed then self:PushSecure() end
    self:ScanUsable()
  end

  -- Mana per slot (spec.manaTint): st.noMana[i] is true while the learned
  -- aspect there cannot be afforded, so the view paints it in the cooldown
  -- grid's no-mana blue. Asked at the learned rank's id. A secret read (in
  -- combat, if the client hides it) or an unknown one is nil: the normal look.
  -- Event-driven (SPELL_UPDATE_USABLE, the spellbook, an open), never per tick.
  function Ring:ScanUsable()
    if not spec.manaTint then return end
    local st = state()
    local usableOf = Nock.API.SpellUsable
    local plain = Nock.Flavor.Plain
    for i = 1, n do
      local flag = nil
      if usableOf and st.known[i] and st.castId[i] then
        local usable, noMana = usableOf(st.castId[i])
        if type(plain(usable)) == "boolean" and plain(noMana) == true then flag = true end
      end
      st.noMana[i] = flag
    end
  end

  function Ring:Refresh(_)
    if state().open then self:UpdateHover() end
    -- The screen size the snippet scales the cursor by: captured at login it
    -- can predate the UI scale (2133x1200 stored vs 2560x1440 live put the
    -- ring at 83 % of the cursor's distance, 2026-09-26). Out of combat, a
    -- mismatch is re-pushed; the compare is all a tick costs.
    if self._armed and not InCombatLockdown()
       and (UIParent:GetWidth() ~= self._sw or UIParent:GetHeight() ~= self._sh) then
      self:PushSecure()
    end
  end

  return Ring
end

-- The aspect ring itself.
Nock.NewRingModule({
  name = "AspectRing", button = "NockAspectRingButton", screen = "NockAspectRingScreen", layer = "NockAspectRingLayer",
  stateKey = "aspectRing", n = 6, prefix = "aspect",
  keyProfile = "aspectRingKey", scaleProfile = "aspectRingScale",
  configMsg = "NOCK_ASPECT_RING_CONFIG", closeMsg = "NOCK_ASPECT_RING_CLOSE",
  idByKey = Nock.AspectRingIdByKey,
  order = function(p) return Nock.AspectRingOrder(p.aspectRingOrder) end,
  manaTint = true,
})
