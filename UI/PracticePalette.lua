-- UI/PracticePalette.lua
-- The proc palette, shared by the practice panel and the expert combat log: one React slot per proc (RF, Lust, Drums, DST, Pot, the QS roll, the KC indicator), a click pops or clears it on the sim.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local Skin = Nock.Skin
Nock.UI = Nock.UI or {}

local Palette = {}
Palette.__index = Palette
Nock.UI.PracticePalette = Palette

-- The proc palette, left to right. `name` is the engine's own proc key (and the
-- symbol Nock.UI.PracticeIconFor resolves); `dur` names the cfg field holding
-- that proc's length; `cd` names the cfg.cooldowns / engine cdReady key, absent
-- for the ones with no cooldown of their own (Lust, DST, and the QS roll).
-- `kind` marks the two read-only tiles: QS's click toggles the roll rather than
-- popping the proc, and KC is an indicator the crits drive.
Palette.SPECS = {
  { name = "RF",    dur = "rfDur",    cd = "RF"    },
  { name = "Lust",  dur = "lustDur"                },
  { name = "Drums", dur = "drumsDur", cd = "Drums" },
  { name = "DST",   dur = "dstDur"                 },
  { name = "Pot",   dur = "potDur",   cd = "Pot"   },
  { name = "QS",    dur = "qsDur",                 kind = "qs" },
  { name = "KC",    dur = "kcWindow", cd = "KC",   kind = "kc" },
}

local function practice() return Nock:GetModule("Practice", true) end

local function profile(key, fallback)
  local p = Nock.db and Nock.db.profile and Nock.db.profile[key]
  if p ~= nil then return p end
  return fallback
end

-- True while `name` is running on the practice engine. Between fights there is
-- no engine, so every proc reads off.
local function procUp(p, name)
  local e = p and p.engine
  local t = e and e.procs and e.procs[name]
  return (t and t > 0) and true or false
end

local function tipEnter(btn)
  if not btn.tipTitle then return end
  GameTooltip:SetOwner(btn, "ANCHOR_BOTTOM")
  GameTooltip:AddLine(btn.tipTitle, 1, 0.82, 0.2)
  if btn.tipText then GameTooltip:AddLine(btn.tipText, 0.8, 0.8, 0.8, true) end
  GameTooltip:Show()
end
local function tipLeave() GameTooltip:Hide() end

-- Build one on `parent`: a row frame (`pal.frame`, anchored and widened by
-- the caller) holding one slot per spec, `size` square, `gap` apart. A slot is
-- desaturated while its proc is down, with a swipe that runs backwards for
-- the remaining duration and forwards for a cooldown.
function Palette.New(parent, size, gap)
  local pal = setmetatable({ slots = {}, order = {}, _n = 0, size = size, gap = gap }, Palette)
  local row = CreateFrame("Frame", nil, parent)
  row:SetSize(#Palette.SPECS * (size + gap), size + 4)
  pal.frame = row
  for i = 1, #Palette.SPECS do
    local spec = Palette.SPECS[i]
    local slot = Nock.UI.CreateReactSlot(row, nil, size)
    slot:SetPoint("TOPLEFT", row, "TOPLEFT", (i - 1) * (size + gap), 0)
    slot.spec = spec
    slot.item = {}          -- reused every tick: Paint never allocates
    slot._cdStart, slot._cdDur, slot._cdRev = nil, nil, nil

    local cd = CreateFrame("Cooldown", nil, slot, "CooldownFrameTemplate")
    cd:SetAllPoints(slot.icon)
    cd:SetDrawEdge(false)
    cd:SetFrameLevel(slot:GetFrameLevel() + 1)
    -- The slot draws its own countdown (PaintReactSlot), so the Blizzard number
    -- would sit on top of ours. The setter is missing on some client builds.
    if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
    -- ...and when it is, suppress the template's own FontStrings directly, the
    -- same fallback Frame_PetStatus and the Widgets cooldown slot use. Filtered
    -- to FontStrings on purpose: the swipe must survive this loop.
    for _, region in ipairs({ cd:GetRegions() }) do
      if region and region.GetObjectType and region:GetObjectType() == "FontString" then
        region:SetAlpha(0)
        region:Hide()
      end
    end
    slot.cd = cd

    -- The swipe is a FRAME one level above the slot, so it paints over the
    -- slot's own time/label FontStrings — they are regions ON the slot. Lift
    -- them onto a text layer above the cooldown (the Widgets / Frame_PetStatus
    -- pattern). A re-parented FontString keeps its anchors, but re-assert the
    -- draw layer rather than trust the default on the new parent.
    local textLayer = CreateFrame("Frame", nil, slot)
    textLayer:SetAllPoints(slot)
    textLayer:SetFrameLevel(cd:GetFrameLevel() + 1)
    slot.time:SetParent(textLayer)
    slot.time:SetDrawLayer("OVERLAY")
    slot.label:SetParent(textLayer)
    slot.label:SetDrawLayer("OVERLAY")
    slot.textLayer = textLayer

    -- The name lives in the tooltip; the icon carries it the rest of the time.
    slot:EnableMouse(true)
    slot.tipTitle = spec.name
    slot.tipText = (spec.kind == "kc" and "Kill Command window — the crits open it.")
      or (spec.kind == "qs" and "Click to pop Quick Shots now; again to hold it for the fight; a third click clears it. Right-click rolls the proc in or out of the drill.")
      or "Click to pop this proc. Click again to hold it for the rest of the fight. A third click, or a right-click, clears it."
    slot:SetScript("OnEnter", tipEnter)
    slot:SetScript("OnLeave", tipLeave)
    -- One closure per slot, built here — never per tick. KC is an indicator
    -- (crits open it), so it answers no click at all.
    -- The cycle (user, 2026-08-27): off -> up (timed, as before) -> held for
    -- the rest of the fight -> off; a right-click is off from anywhere. A
    -- tile the SCENARIO holds answers nothing. QS is the one exception on the
    -- RIGHT button: it rolls the proc in or out of the drill (the old click),
    -- the left button cycling the proc itself like any other tile.
    if spec.kind ~= "kc" then
      slot:SetScript("OnMouseUp", function(_, button)
        local p = practice()
        if not p then return end
        if spec.kind == "qs" and button == "RightButton" then
          p:ToggleQS()
          return
        end
        local st = (p.ProcState and p:ProcState(spec.name)) or (procUp(p, spec.name) and "up" or "off")
        if st == "held" then return end
        local mode
        if button == "RightButton" then mode = "off"
        elseif st == "off" then mode = "on"
        elseif st == "up" then mode = "perm"
        else mode = "off" end
        if p.ProcMode then p:ProcMode(spec.name, mode)
        elseif p.Proc then p:Proc(spec.name, mode ~= "off") end
      end)
    end
    pal.slots[i] = slot
  end
  return pal
end

function Palette:Count() return self._n or 0 end

-- Which tiles this drill lets you touch, seated left to right; returns the
-- count (0: hide the row). A paper drill (`paper`) pins its haste AND its
-- Quick Shots roll, so nothing on the row would answer a click: the row goes
-- away rather than sitting there greyed — the stage's PROCS lane is where a
-- pinned drill's procs are read. A proc the scenario HOLDS up for the whole
-- fight is not yours to pop either. KC is an indicator, so it rides along only
-- when at least one real tile does.
function Palette:Resolve(p, paper)
  local order = self.order
  -- Cleared by the LAST count, not by `#order`: nil-ing index 1 makes the
  -- length operator's answer undefined halfway through the loop.
  for i = 1, (self._n or 0) do order[i] = nil end
  local sc = (p and p.CurrentScenario) and (p:CurrentScenario()) or nil
  -- While a fight runs the ENGINE's copy of the SCENARIO's holds is the one in
  -- force: the picker may have moved on since the pull. (Not `e.hold`: that
  -- also carries the player's own hand-made holds, which must stay clickable.)
  local hold = (Nock.state.sim.fightOn and p and p.engine and p.engine.scHold) or (sc and sc.hold) or nil
  local qsOff = (sc and sc.qs == false) and true or false
  local kc
  local n = 0
  for i = 1, #self.slots do
    local slot = self.slots[i]
    local spec = slot.spec
    local ok
    if paper then
      -- A paper drill pins its procs, so nothing is yours to pop -- until a
      -- proc KEY pops one (Practice:ProcMode files it in `_procSeen`): that
      -- proc's tile shows for the rest of the fight, so its state can be
      -- read and cycled. KC never (a paper rolls no crits).
      ok = spec.kind ~= "kc" and p and p._procSeen and p._procSeen[spec.name] and true or false
    elseif spec.kind == "kc" then ok = false; kc = slot
    elseif spec.kind == "qs" then ok = not qsOff
    else ok = not (hold and hold[spec.name]) end
    slot._shown = ok and true or false
    if ok then
      n = n + 1
      order[n] = slot
    end
  end
  if kc and n > 0 then
    n = n + 1
    order[n] = kc
    kc._shown = true
  end
  for i = 1, n do
    local slot = order[i]
    slot:ClearAllPoints()
    slot:SetPoint("TOPLEFT", self.frame, "TOPLEFT", (i - 1) * (self.size + self.gap), 0)
    slot:Show()
  end
  for i = 1, #self.slots do
    local slot = self.slots[i]
    if not slot._shown then slot:Hide() end
  end
  self._n = n
  return n
end

-- Once per tick. Every texture/text mutation is diffed inside PaintReactSlot,
-- and the cooldown frame is touched only when its (start, duration,
-- direction) signature actually moves — SetCooldown restarts the swipe, so
-- calling it every tick would freeze it at full. The `item` tables are built
-- once in New: nothing here allocates.
function Palette:Paint(p, now)
  local n = self._n or 0
  if n == 0 then return end
  local e = p and p.engine
  local cfg = e and e.cfg
  -- The engine's copy is what the running fight actually rolls on (a scenario
  -- may take the roll away for its fight); the profile only decides before the
  -- first pull.
  local qsOn
  if cfg then qsOn = cfg.quickShots and true or false
  else qsOn = profile("practiceQuickShots", true) and true or false end
  local holds = e and e.hold
  local scHolds = e and e.scHold
  for i = 1, n do
    local slot = self.order[i]
    local spec, item = slot.spec, slot.item
    -- Up: the proc's until-time (KC's window is the engine's own kcUntil).
    local up, exp, dur = false, 0, 0
    if spec.kind == "kc" then
      local kcU = (e and e.kcUntil) or 0
      if kcU > now then up, exp, dur = true, kcU, (cfg and cfg.kcWindow) or 0 end
    else
      local t = (e and e.procs and e.procs[spec.name]) or 0
      if t > now then up, exp, dur = true, t, (cfg and cfg[spec.dur]) or 0 end
    end
    -- Down, but its cooldown is still running: the same ring, forwards.
    if not up and spec.cd and cfg and e.cdReady then
      local r = e.cdReady[spec.cd] or 0
      if r > now then exp, dur = r, cfg.cooldowns[spec.cd] or 0 end
    end
    -- A HELD proc (a paper drill's `hold=`) is parked at now + 1e9 by the
    -- engine. Handing that to the swipe (or to the slot's countdown text)
    -- renders the sentinel; it has no expiry to draw, so it gets none.
    local held = (up and holds and holds[spec.name]) and true or false
    if held then exp, dur = 0, 0 end

    local start, cddur = 0, 0
    if dur > 0 and exp > now then start, cddur = exp - dur, dur end
    if start ~= slot._cdStart or cddur ~= slot._cdDur or up ~= slot._cdRev then
      slot._cdStart, slot._cdDur, slot._cdRev = start, cddur, up
      slot.cd:SetReverse(up)   -- a proc counts DOWN, a cooldown fills up
      slot.cd:SetCooldown(start, cddur)
    end

    -- Bottom caption inside the tile: the scenario's hold ("held", not yours),
    -- your own ("perm": the next click clears it), or why QS won't answer.
    local sub
    if held then sub = (scHolds and scHolds[spec.name]) and "held" or "perm"
    elseif spec.kind == "qs" then sub = qsOn and "" or "off"
    else sub = "" end
    item.icon = Nock.UI.PracticeIconFor(spec.name)
    item.desat = (not up) and not held
    item.exp, item.dur, item.sub = exp, dur, sub
    Nock.UI.PaintReactSlot(slot, item, now)
  end
end
