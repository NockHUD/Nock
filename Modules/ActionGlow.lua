-- Modules/ActionGlow.lua
-- Glows the real action-bar button(s) holding Kill Command while its proc is
-- up (profile.kcActionBarGlow) — the reference WA's "Action Button Glow",
-- through LibCustomGlow's Blizzard-style overlay. Works in combat: the overlay
-- is an unprotected frame parented to the button, nothing secure is touched.
--
-- The decision is pure (Modules/ActionGlowEngine.lua): which slots hold the
-- spell, which buttons drive them, what to start/stop. This file owns the
-- events (bar edits, paging, macros) and the proc edge from Cooldowns
-- (NOCK_PROC_ACTIVE). Nothing runs on the tick: the button list is rebuilt on
-- a bar change only, the glow flips on the proc edge only.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local ActionGlow = Nock:NewModule("ActionGlow", "AceEvent-3.0", "AceTimer-3.0")
local C = Nock.Constants
local LCG = LibStub("LibCustomGlow-1.0", true)

local RESCAN_DELAY = 0.2   -- bar events come in bursts (a page flip fires one per slot)

local BAR_EVENTS = {
  "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR",
  "UPDATE_MACROS", "UPDATE_SHAPESHIFT_FORM", "PLAYER_ENTERING_WORLD",
}

local function enabled()
  local p = Nock.db and Nock.db.profile
  return (p and p.kcActionBarGlow) and true or false
end

-- GetMacroSpell returns the spell id on this client (older clients returned
-- name, rank, id); take whichever return is a number.
local function macroSpell(macroId)
  if not GetMacroSpell then return nil end
  local okCall, a, b, c = pcall(GetMacroSpell, macroId)
  if not okCall then return nil end
  return tonumber(c) or tonumber(a) or tonumber(b)
end

function ActionGlow:OnEnable()
  self._glowing  = {}
  self._buttons  = {}
  self._proc     = false
  self._spellIds = { [C.SpellID.KILL_COMMAND] = true }
  for _, ev in ipairs(BAR_EVENTS) do
    pcall(self.RegisterEvent, self, ev, "Rescan")   -- AceEvent hard-errors on an unknown event
  end
  self:RegisterMessage("NOCK_PROC_ACTIVE", "OnProc")
  self:RegisterMessage("NOCK_VISUALS_CHANGED", "Apply")
  self:Rescan()
end

function ActionGlow:OnDisable()
  self._proc = false
  self:Apply()
end

-- Debounced: one rebuild per burst of bar events. Off (the shipped default)
-- the bar is not scanned at all -- a page flip or an aspect switch fired a
-- 120-slot GetActionInfo walk and a ~420-name candidate table for nothing;
-- Apply rescans once when the option comes on.
function ActionGlow:Rescan()
  if not enabled() then self._scanned = false; return end
  if self._rescanTimer then return end
  self._rescanTimer = self:ScheduleTimer(function()
    self._rescanTimer = nil
    self:DoRescan()
  end, RESCAN_DELAY)
end

function ActionGlow:DoRescan()
  local E = Nock.ActionGlowEngine
  if not E or not GetActionInfo then return end
  self._scanned = true
  local slots = E.SlotsFor(GetActionInfo, self._spellIds, macroSpell)
  local cands = {}
  for _, name in ipairs(E.CandidateNames()) do
    local f = _G[name]
    if type(f) == "table" then cands[#cands + 1] = f end
  end
  self._buttons = E.ButtonsFor(slots, cands)
  local cd = Nock.state and Nock.state.cooldowns and Nock.state.cooldowns.KC
  self._proc = (cd and cd.procActive) and true or false
  self:Apply()
end

function ActionGlow:OnProc(_, key, active)
  if key ~= "KC" then return end
  self._lastProcMsg = { key = key, active = active and true or false, at = GetTime and GetTime() or 0 }
  self:OnProcTrace(active)
  self._proc = active and true or false
  self:Apply()
end

-- /nock kcglow [test on|off]: every layer between the proc and the glow, in a
-- copybox. `test on` forces the overlay onto the found buttons whatever the
-- proc says (tells "no buttons found" from "no proc seen"); `test off` clears.
function ActionGlow:Test(on)
  self._forced = on and true or false
  self:Apply()
end

-- The React grid's KC tile, if the grid is built.
local function kcTile()
  local rv = Nock:GetModule("ReactCooldownsView", true)
  if not rv or not rv._pool then return nil end
  for _, slot in ipairs(rv._pool) do
    if slot._entry and slot._entry.key == "KC" then return slot end
  end
  return nil
end

-- /nock kcglow tile on|off|white: force the overlay on the KC tile (coloured
-- as the painter does, or uncoloured like the bar glow), bypassing the look.
function ActionGlow:TestTile(mode)
  local slot = kcTile()
  if not slot then Nock:Print("kcglow: no KC tile in the React grid."); return end
  if mode == "off" then
    Nock.UI.SetIconProcGlow(slot, false)
    slot._lastLook = nil          -- let the painter repaint from the state
  elseif mode == "white" then
    slot._nockProcGlow = nil
    Nock.UI.SetIconProcGlow(slot, true, nil)
  else
    slot._nockProcGlow = nil
    Nock.UI.SetIconProcGlow(slot, true, C.COLORS.PROC_GLOW)
  end
  Nock:Print(("kcglow: tile glow %s"):format(mode))
end

-- /nock kcglow trace: 30 s of evidence for the proc question -- every aura
-- applied/removed on the player (combat log, with ids), every ranged crit,
-- every UnitBuff diff, and every NOCK_PROC_ACTIVE -- then a copybox.
local TRACE_SECS = 30
function ActionGlow:Trace()
  if self._trace then Nock:Print("kcglow: trace already running."); return end
  self._trace = { lines = {}, t0 = GetTime(), buffs = {} }
  self._playerGUID = self._playerGUID or UnitGUID("player")
  local T = self._trace
  local function log(fmt, ...) T.lines[#T.lines + 1] = ("%6.2f  "):format(GetTime() - T.t0) .. fmt:format(...) end
  T.log = log
  log("trace start; procActive=%s", tostring(Nock.state.cooldowns.KC and Nock.state.cooldowns.KC.procActive))
  self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", "TraceCLEU")
  self:RegisterEvent("UNIT_AURA", "TraceAura")
  self:TraceAura(nil, "player")
  self:ScheduleTimer(function() self:TraceStop() end, TRACE_SECS)
  Nock:Print(("kcglow: tracing for %d s -- get a ranged crit now."):format(TRACE_SECS))
end

function ActionGlow:TraceStop()
  local T = self._trace
  if not T then return end
  self:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
  self:UnregisterEvent("UNIT_AURA")
  T.log("trace end; procActive=%s lastProcMsg=%s",
    tostring(Nock.state.cooldowns.KC and Nock.state.cooldowns.KC.procActive),
    self._lastProcMsg and (tostring(self._lastProcMsg.active) .. " @" .. ("%.1f"):format(self._lastProcMsg.at - T.t0)) or "none")
  self._trace = nil
  Nock.UI.ShowCopyBox("Nock KC glow trace\n" .. table.concat(T.lines, "\n"))
end

function ActionGlow:TraceCLEU()
  local T = self._trace
  if not T then return end
  local _, sub, _, srcGUID, _, _, _, dstGUID, _, _, _, a1, a2, a3, a4, a5, a6, a7, a8, a9 = CombatLogGetCurrentEventInfo()
  local me = self._playerGUID
  if dstGUID == me and (sub == "SPELL_AURA_APPLIED" or sub == "SPELL_AURA_REMOVED" or sub == "SPELL_AURA_REFRESH") then
    T.log("%s  %s (id %s) %s", sub:sub(12), tostring(a2), tostring(a1), tostring(a4))
  elseif srcGUID == me and (sub == "SPELL_DAMAGE" or sub == "RANGE_DAMAGE") then
    -- spellId, spellName, school, amount, overkill, school, resisted, blocked, absorbed, critical
    local _, _, _, _, _, _, _, _, _, _, _, sid, sname, _, amount, _, _, _, _, _, critical = CombatLogGetCurrentEventInfo()
    if critical then T.log("CRIT  %s (id %s) %s", tostring(sname), tostring(sid), tostring(amount)) end
  elseif srcGUID == me and sub == "SPELL_CAST_SUCCESS" then
    if a2 == "Kill Command" then T.log("CAST  Kill Command") end
  end
end

function ActionGlow:TraceAura(_, unit)
  local T = self._trace
  if not T or unit ~= "player" then return end
  local now = {}
  for i = 1, 40 do
    local name, _, _, _, dur, _, _, _, _, id = UnitBuff("player", i)
    if not name then break end
    now[id or name] = name
    if not T.buffs[id or name] then T.log("+buff %s (id %s) dur=%s", name, tostring(id), tostring(dur)) end
  end
  for k, name in pairs(T.buffs) do
    if not now[k] then T.log("-buff %s (id %s)", name, tostring(k)) end
  end
  T.buffs = now
end

function ActionGlow:OnProcTrace(active)
  if self._trace then self._trace.log("NOCK_PROC_ACTIVE KC=%s", tostring(active)) end
end

function ActionGlow:Diag()
  local E = Nock.ActionGlowEngine
  local p = Nock.db and Nock.db.profile or {}
  local L = {}
  local function add(fmt, ...) L[#L + 1] = fmt:format(...) end
  add("Nock KC glow diag  %s", date and date("%H:%M:%S") or "")
  add("options: kcActionBarGlow=%s reactKcProcGlow=%s reactRangeTint=%s hudMode=%s",
      tostring(p.kcActionBarGlow), tostring(p.reactKcProcGlow), tostring(p.reactRangeTint), tostring(p.hudMode))
  local lcgMinor = LibStub and select(2, LibStub("LibCustomGlow-1.0", true))
  add("LibCustomGlow: %s (minor %s)  ButtonGlow_Start=%s", tostring(LCG ~= nil), tostring(lcgMinor),
      tostring(LCG and LCG.ButtonGlow_Start ~= nil))
  add("engine: %s  GetActionInfo=%s GetMacroSpell=%s", tostring(E ~= nil),
      tostring(GetActionInfo ~= nil), tostring(GetMacroSpell ~= nil))
  local cd = Nock.state and Nock.state.cooldowns and Nock.state.cooldowns.KC
  add("state.cooldowns.KC: %s procActive=%s spellId=%s ready=%s", tostring(cd ~= nil),
      tostring(cd and cd.procActive), tostring(cd and cd.spellId), tostring(cd and cd.ready))
  local usA = C_Spell and C_Spell.IsSpellUsable and tostring(C_Spell.IsSpellUsable(34026)) or "n/a"
  local usB = IsUsableSpell and tostring(IsUsableSpell(34026)) or "n/a"
  add("Kill Command usable now: C_Spell.IsSpellUsable=%s IsUsableSpell=%s (the WA's proc signal)", usA, usB)
  add("module: proc=%s forced=%s buttons=%d glowing=%d lastProcMsg=%s",
      tostring(self._proc), tostring(self._forced),
      (function() local n = 0; for _ in pairs(self._buttons or {}) do n = n + 1 end; return n end)(),
      (function() local n = 0; for _ in pairs(self._glowing or {}) do n = n + 1 end; return n end)(),
      self._lastProcMsg and ("%s=%s @%.1f"):format(self._lastProcMsg.key, tostring(self._lastProcMsg.active), self._lastProcMsg.at) or "none")
  -- Auras on the player mentioning Kill Command, with their ids: the fact the
  -- proc matching depends on (34027 procBuff vs 34026 spell id).
  add("player auras mentioning Kill Command:")
  local found = 0
  for i = 1, 40 do
    local name, icon, _, _, dur, exp, _, _, _, id = UnitBuff("player", i)
    if not name then break end
    if name:find("Kill Command") or id == 34026 or id == 34027 then
      found = found + 1
      add("  buff %d: %s id=%s dur=%s exp=%s", i, name, tostring(id), tostring(dur), tostring(exp))
    end
  end
  if found == 0 then add("  (none right now)") end
  -- Slots and buttons, resolved fresh.
  if E and GetActionInfo then
    local slots = E.SlotsFor(GetActionInfo, self._spellIds or {}, macroSpell)
    local sl = {}
    for slot in pairs(slots) do sl[#sl + 1] = slot end
    table.sort(sl)
    add("action slots holding Kill Command: %s", #sl > 0 and table.concat(sl, ", ") or "NONE")
    for _, slot in ipairs(sl) do
      local kind, id = GetActionInfo(slot)
      add("  slot %d: %s %s", slot, tostring(kind), tostring(id))
    end
    local fams, hits = {}, {}
    for _, name in ipairs(E.CandidateNames()) do
      local f = _G[name]
      if type(f) == "table" then
        local fam = name:gsub("%d+$", "")
        fams[fam] = (fams[fam] or 0) + 1
        local s2 = E.FrameSlot(f)
        if s2 and slots[s2] then
          hits[#hits + 1] = ("%s -> slot %d (shown=%s)"):format(name, s2,
            tostring(type(f.IsShown) == "function" and f:IsShown()))
        end
      end
    end
    local fl = {}
    for fam, n in pairs(fams) do fl[#fl + 1] = fam .. " x" .. n end
    table.sort(fl)
    add("bar frames present: %s", #fl > 0 and table.concat(fl, ", ") or "NONE")
    add("buttons driving a KC slot: %s", #hits > 0 and "" or "NONE")
    for _, h in ipairs(hits) do add("  %s", h) end
    -- Dominos sanity: what does its first button carry?
    local d1 = _G["DominosActionButton1"]
    if d1 then
      add("DominosActionButton1: .action=%s _state_action=%s attr=%s", tostring(d1.action),
          tostring(d1._state_action), tostring(d1.GetAttribute and d1:GetAttribute("action")))
    end
  end
  -- Per-slot range: both API forms against the current target, and what
  -- RangeFinder published (state.target.spellOut). Raptor Strike is the one
  -- to watch: a "next melee" ability may answer the id form differently.
  add("range per slot (target=%s):", tostring(UnitExists("target") and UnitName("target") or "none"))
  local so = Nock.state.target and Nock.state.target.spellOut or {}
  local keys = {}
  for key, st in pairs(Nock.state.cooldowns) do if st.spellId then keys[#keys + 1] = key end end
  table.sort(keys)
  for _, key in ipairs(keys) do
    local id = Nock.state.cooldowns[key].spellId
    local byId = "n/a"
    if C_Spell and C_Spell.IsSpellInRange then byId = tostring(C_Spell.IsSpellInRange(id, "target")) end
    local nm
    if C_Spell and C_Spell.GetSpellInfo then local i = C_Spell.GetSpellInfo(id); nm = i and i.name
    elseif GetSpellInfo then nm = GetSpellInfo(id) end
    local byName = "n/a"
    if IsSpellInRange and nm then byName = tostring(IsSpellInRange(nm, "target")) end
    add("  %-8s id=%-6s %-16s byId=%-5s byName=%-5s spellOut=%s", key, tostring(id), tostring(nm), byId, byName, tostring(so[key]))
  end
  -- The React KC tile: the look the painter decided, and the overlay frame.
  local slot = kcTile()
  if not slot then
    add("React KC tile: not in the grid (grid hidden, KC slot disabled, or Classic mode)")
  else
    local p2 = Nock.db.profile
    local vis, glow, desat, red = Nock.UI.ReactSlotLook(cd or {}, nil,
      { procGlow = p2.reactKcProcGlow and true or false, tint = p2.reactRangeTint or "off", whenActive = slot._whenActive })
    add("React KC tile: shown=%s size=%.0fx%.0f level=%s strata=%s", tostring(slot:IsShown()),
        slot:GetWidth(), slot:GetHeight(), tostring(slot:GetFrameLevel()), tostring(slot:GetFrameStrata()))
    add("  look now: vis=%s glow=%s desat=%s red=%s  | painter _lastLook=%s _nockProcGlow=%s",
        vis, tostring(glow), tostring(desat), tostring(red), tostring(slot._lastLook), tostring(slot._nockProcGlow))
    local g = slot._ButtonGlow
    if g then
      add("  _ButtonGlow: shown=%s alpha=%.2f size=%.0fx%.0f level=%s parent=%s color=%s animIn=%s",
          tostring(g:IsShown()), g:GetAlpha(), g:GetWidth(), g:GetHeight(), tostring(g:GetFrameLevel()),
          tostring(g:GetParent() == slot), tostring(g.color and "set" or "none"),
          tostring(g.animIn and g.animIn:IsPlaying()))
      local t = g.innerGlow
      if t then add("  innerGlow: alpha=%.2f shown=%s", t:GetAlpha(), tostring(t:IsShown())) end
    else
      add("  _ButtonGlow: none (ButtonGlow_Start never ran on this tile)")
    end
    add("  border glow frame shown=%s", tostring(slot.glow and slot.glow:IsShown()))
  end
  Nock.UI.ShowCopyBox(table.concat(L, "\n"))
end

function ActionGlow:Apply()
  local E = Nock.ActionGlowEngine
  if not E or not LCG or not LCG.ButtonGlow_Start then return end
  if enabled() and not self._scanned then self:Rescan() end
  local want = E.Wanted(enabled() or self._forced, self._proc or self._forced, self._buttons or {})
  local start, stop = E.Diff(self._glowing, want)
  for _, f in ipairs(stop)  do pcall(LCG.ButtonGlow_Stop, f) end
  for _, f in ipairs(start) do pcall(LCG.ButtonGlow_Start, f, nil, 0.3) end
  if #start > 0 or #stop > 0 then
    local g = {}
    for f in pairs(want) do g[f] = true end
    self._glowing = g
  end
end
