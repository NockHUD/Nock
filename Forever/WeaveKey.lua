-- Forever/WeaveKey.lua
-- The Forever weave key: one held key runs you in and out through the Movement Pad and its release edge strikes or shoots; an optional mode beside the macro way.

-- Spec: docs/superpowers/specs/2026-09-29-forever-weave-key-design.md.
-- The button is a SecureActionButtonTemplate with both click edges; the
-- wrapped OnClick swaps macrotext per edge (the TBC WeaveBind recipe). Both
-- bodies are the user's text; the stock ones below are what the dummy runs
-- proved (5/5 strikes, the shot 0.5 s after the range release). Addons
-- cannot start or stop movement or cast: every edge is the player's.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local WeaveKey = Nock:NewModule("WeaveKey", "AceEvent-3.0")
Nock.WeaveKey = WeaveKey

WeaveKey.BUTTON = "NockWeaveKey"
WeaveKey.PAD_LINE = "/click MovePadForward"
WeaveKey.STOCK_DOWN = "/click MovePadForward"
-- The last two lines: NockCamFlip() arms the turn away for the hit (ignored
-- while already turned), NockCamFace() turns back when a turn is outstanding
-- (a no-op otherwise), so the range release faces the target on its own
-- whatever the "Turn back when in range" switch says.
WeaveKey.STOCK_UP = "/click MovePadForward\n/stopcasting\n/cast Raptor Strike\n/startattack\n/cast !Auto Shot\n/run NockCamFlip()\n/run NockCamFace()"
WeaveKey.STUCK_AFTER = 1.0   -- s a pad toggle may read checked with no key held
WeaveKey.HOLD_STALE = 10     -- s after which a press with no release counts as released
WeaveKey.EDGE_MAX = 20
WeaveKey.refreshInterval = 0.25   -- the watchdog lane

-- Pure: the mode switch (off unless set).
function WeaveKey.Enabled(p)
  return p ~= nil and p.weaveKeyEnabled == true
end

-- Pure: the two bodies. nil = never set = stock; "" = the user emptied it.
function WeaveKey.Bodies(p)
  local d = p and p.weaveKeyMacroDown
  local u = p and p.weaveKeyMacroUp
  if d == nil then d = WeaveKey.STOCK_DOWN end
  if u == nil then u = WeaveKey.STOCK_UP end
  return d, u
end

-- Lines, normalised: CR dropped, blanks trimmed, trailing empty lines
-- dropped (the same reading Core/WeaveMacro.lua gives a body).
local function norm(text)
  local out = {}
  for line in ((text or "") .. "\n"):gmatch("(.-)\n") do
    line = line:gsub("\r", ""):gsub("^%s+", ""):gsub("%s+$", "")
    out[#out + 1] = line
  end
  while #out > 0 and out[#out] == "" do out[#out] = nil end
  return table.concat(out, "\n")
end

-- Pure: is `text` the stock body, give or take whitespace?
function WeaveKey.IsStock(text, stock)
  return norm(text) == norm(stock)
end

-- Pure: every pad button a body clicks, in order, once each.
function WeaveKey.PadButtons(text)
  local out, seen = {}, {}
  for line in ((text or "") .. "\n"):gmatch("(.-)\n") do
    local name = line:match("^%s*/click%s+(MovePad%w+)")
    if name and not seen[name] then seen[name] = true; out[#out + 1] = name end
  end
  return out
end

-- Pure: the stuck-toggle decision. A pad button checked while no key is held
-- (a release edge lost to death, alt-tab, a loading screen) keeps the
-- character running; addon code cannot heal it, so the caller tells the fix
-- once per incident. `st` remembers since when and whether it was told.
function WeaveKey.Stuck(st, checkedAny, held, heldSince, now)
  if held and now - (heldSince or now) < WeaveKey.HOLD_STALE then
    st.since = nil
    return false
  end
  if not checkedAny then
    st.since, st.told = nil, false
    return false
  end
  st.since = st.since or now
  if st.told or now - st.since < WeaveKey.STUCK_AFTER then return false end
  st.told = true
  return true
end

-- Pure: the copybox text (/nock weavekey). d = { enabled, key, down, up,
-- built, bound, padLoaded, flipOn, pad = {{name, checked}}, edges = {{t, down,
-- zone, mrem, combat}}, casts = {{t, ev, name}} }.
function WeaveKey.Report(d)
  local L = {}
  local function row(s) L[#L + 1] = s end
  local function lines(s) return (tostring(s or ""):gsub("\n", " | ")) end
  row(("Weave key  mode: %s  key: %s  built: %s  bound: %s  pad loaded: %s  camera flip: %s"):format(
    d.enabled and "on" or "off", tostring(d.key), tostring(d.built), tostring(d.bound), tostring(d.padLoaded), d.flipOn and "on" or "off"))
  row("press:\n" .. lines(d.down))
  row("release:\n" .. lines(d.up))
  local pad = {}
  for _, b in ipairs(d.pad or {}) do pad[#pad + 1] = b.name .. " checked " .. tostring(b.checked) end
  row("pad: " .. (#pad > 0 and table.concat(pad, "  ") or "none named"))
  row("")
  local all = {}
  for _, e in ipairs(d.edges or {}) do
    all[#all + 1] = { t = e.t, s = ("%s  zone %s  meleeIn %.2f  combat %s"):format(e.down and "press" or "release",
      tostring(e.zone), e.mrem or 0, tostring(e.combat)) }
  end
  for _, c in ipairs(d.casts or {}) do
    all[#all + 1] = { t = c.t, s = ("cast %s  %s"):format(tostring(c.ev), tostring(c.name)) }
  end
  table.sort(all, function(a, b) return a.t < b.t end)
  row("timeline (t  event  detail):")
  for _, e in ipairs(all) do row(("  %.3f  %s"):format(e.t, e.s)) end
  return table.concat(L, "\n")
end

--------------------------------------------------------------------------------
-- Runtime
--------------------------------------------------------------------------------

local WRAP_ONCLICK = [[
  if down then
    self:SetAttribute("useOnKeyDown", true)
    self:SetAttribute("macrotext", self:GetAttribute("macrotextDown") or "")
  else
    self:SetAttribute("useOnKeyDown", false)
    self:SetAttribute("macrotext", self:GetAttribute("macrotextUp") or "")
  end
]]

local function profile() return Nock.db and Nock.db.profile end
local function inCombat() return Nock.Flavor.Plain(_G.InCombatLockdown and _G.InCombatLockdown()) == true end

function WeaveKey:Say(msg)
  Nock:Print("Weave key: " .. msg)
end

function WeaveKey:OnEnable()
  self._edges, self._stuck = {}, {}
  self:RegisterEvent("PLAYER_REGEN_ENABLED")
  -- A lost release edge (death, a loading screen) would leave keyHeld true
  -- and the watchdog quiet for HOLD_STALE: drop the hold at once.
  self:RegisterEvent("PLAYER_DEAD", "OnHoldLost")
  self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnHoldLost")
  self:RegisterMessage("NOCK_WEAVEKEY_CHANGED", "Apply")
  -- The core sends this on every profile switch, copy, reset and import
  -- (Core/Core.lua OnProfileSwitched): the key follows the new profile.
  self:RegisterMessage("NOCK_WEAVEBIND_CHANGED", "Apply")
  self:Apply()
end

function WeaveKey:OnHoldLost()
  local w = Nock.state and Nock.state.weave
  if w and w.keyHeld then w.keyHeld = false end
end

-- Blizzard_MovePad is load-on-demand; both loaders are tried. True when the
-- forward button exists afterwards.
function WeaveKey:LoadPad()
  if _G.MovePadForward then return true end
  if _G.MovePad_LoadUI then pcall(_G.MovePad_LoadUI) end
  if not _G.MovePadForward and _G.C_AddOns and _G.C_AddOns.LoadAddOn then pcall(_G.C_AddOns.LoadAddOn, "Blizzard_MovePad") end
  return _G.MovePadForward ~= nil
end

-- The secure button, once, out of combat.
function WeaveKey:Build()
  if self.button then return true end
  if inCombat() then return false end
  local b = CreateFrame("Button", WeaveKey.BUTTON, UIParent, "SecureActionButtonTemplate")
  b:SetAttribute("type", "macro")
  b:RegisterForClicks("AnyDown", "AnyUp")
  SecureHandlerWrapScript(b, "OnClick", b, WRAP_ONCLICK)
  b:HookScript("PostClick", function(_, _, down) WeaveKey:OnEdge(down) end)
  self.button = b
  return true
end

-- Bodies and binding from the profile. The bodies follow the MODE (the
-- game's own Key Bindings entry can click the button without Nock's key);
-- Nock's override binding follows the key. Mode off empties both bodies so
-- a game binding runs nothing. Secure attributes and binding calls are
-- protected in combat: a change made there lands when combat ends.
function WeaveKey:Apply()
  if inCombat() then self._pending = true; return end
  self._pending = nil
  local p = profile()
  local key = p and p.weaveKey
  local on = WeaveKey.Enabled(p)
  if on and not self:LoadPad() then
    if not self._padWarned then
      self._padWarned = true
      self:Say("the Movement Pad is not available on this client, so the key cannot run you.")
    end
    on = false
  end
  if not self.button and not on then return end
  if not self:Build() then return end
  local b = self.button
  ClearOverrideBindings(b)
  if not on then
    b:SetAttribute("macrotextDown", "")
    b:SetAttribute("macrotextUp", "")
    return
  end
  local d, u = WeaveKey.Bodies(p)
  b:SetAttribute("macrotextDown", d)
  b:SetAttribute("macrotextUp", u)
  if type(key) == "string" and key ~= "" then SetOverrideBindingClick(b, true, key, WeaveKey.BUTTON) end
  local CF = Nock.CameraFlip
  if CF and CF.Enabled and not CF.Enabled(p) and not self._flipWarned then
    self._flipWarned = true
    self:Say("the camera flip is off: the second hold runs you toward the target. Utilities > Camera flip turns it on.")
  end
end

function WeaveKey:PLAYER_REGEN_ENABLED()
  if self._pending then self:Apply() end
end

-- The insecure side of a click: bookkeeping only, never an attribute.
function WeaveKey:OnEdge(down)
  local now = GetTime()
  local st = Nock.state
  local w = st and st.weave
  if w then
    w.keyHeld = down == true
    if down then w.keyHeldSince = now end
  end
  local m = st and st.melee
  local E = self._edges
  E[#E + 1] = { t = now, down = down == true, zone = st and st.target and st.target.rangeState,
    mrem = (m and m.swingStart and m.swingStart > 0) and (m.swingRemaining or 0) or 0, combat = inCombat() }
  if #E > WeaveKey.EDGE_MAX then table.remove(E, 1) end
end

-- The watchdog lane (refreshInterval): a pad toggle left on by a lost
-- release edge keeps the character running; say the fix once.
function WeaveKey:Refresh(state)
  local p = profile()
  if not WeaveKey.Enabled(p) then return end
  local d, u = WeaveKey.Bodies(p)
  local checkedName
  for _, text in ipairs({ d, u }) do
    for _, name in ipairs(WeaveKey.PadButtons(text)) do
      local b = _G[name]
      if b and b.GetChecked and b:GetChecked() == true then checkedName = checkedName or name end
    end
  end
  local w = state and state.weave
  if WeaveKey.Stuck(self._stuck, checkedName ~= nil, w and w.keyHeld, w and w.keyHeldSince, GetTime()) then
    -- The weave key itself is a click PAIR and never re-syncs a toggle; one
    -- extra click does (Modules/WeaveBind.lua's watchdog, the same lesson).
    self:Say(("a Movement Pad toggle is stuck on (a release edge was lost), so you keep running. Type /click %s once to stop and re-sync."):format(checkedName))
  end
end

function WeaveKey:Data()
  local p = profile() or {}
  local d, u = WeaveKey.Bodies(p)
  local pad = {}
  for _, text in ipairs({ d, u }) do
    for _, name in ipairs(WeaveKey.PadButtons(text)) do
      local b = _G[name]
      pad[#pad + 1] = { name = name, checked = b and b.GetChecked and (b:GetChecked() == true) or false }
    end
  end
  local casts, P, API = {}, Nock.ForeverProbe, Nock.API
  for _, c in ipairs((P and P.Casts) and P:Casts() or {}) do
    local n = c.spellID and API and API.SpellName and Nock.Flavor.Plain(API.SpellName(c.spellID))
    casts[#casts + 1] = { t = c.t, ev = (c.ev or ""):gsub("UNIT_SPELLCAST_", ""), name = type(n) == "string" and n or tostring(c.spellID) }
  end
  local CF = Nock.CameraFlip
  return {
    enabled = WeaveKey.Enabled(p), key = p.weaveKey, down = d, up = u, built = self.button ~= nil,
    bound = WeaveKey.Enabled(p) and type(p.weaveKey) == "string" and p.weaveKey ~= "" and self.button ~= nil and not self._pending,
    padLoaded = _G.MovePadForward ~= nil, flipOn = CF and CF.Enabled and CF.Enabled(p) or false,
    pad = pad, edges = self._edges or {}, casts = casts,
  }
end

-- /nock weavekey: the report in a copybox.
function WeaveKey:Command(rest)
  local text = WeaveKey.Report(self:Data())
  if Nock.UI and Nock.UI.ShowCopyBox then Nock.UI.ShowCopyBox(text) else Nock:Print(text) end
end
