-- Modules/Profiler.lua
-- Opt-in performance profiler: per-module tick timing AND allocation, tick-rate,
-- event-rate, nameplate-count sampling and the addon's memory figure. Zero
-- overhead when stopped (Nock._prof is nil, so Core:Tick never touches it and
-- no events are registered). Drives the /nock profile slash family and an
-- optional live on-screen overlay.
--
-- Memory: a raid's "Nock uses 100 MB" is garbage between GC cycles, not a
-- leak, and the only way to say WHICH module makes it is to measure the Lua
-- heap (collectgarbage("count"), KB) across each Refresh and each scan. The
-- KB/s column is that; the addon total is GetAddOnMemoryUsage, refreshed on
-- report only (UpdateAddOnMemoryUsage walks every addon and is not cheap).

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local Profiler = Nock:NewModule("Profiler", "AceTimer-3.0", "AceConsole-3.0")

local CORE_KEY       = "(core-body)"
local SAMPLE_INTERVAL = 0.25   -- nameplate-count sampler
local OVERLAY_INTERVAL = 1     -- the panel's own refresh (a timer, never per-frame)
local CAPTURE_MAX      = 60    -- a Capture stops itself after this many seconds

-- ---------------------------------------------------------------------------
-- Timer source. debugprofilestop() returns milliseconds with sub-ms precision
-- and needs no CVar / reload (unlike GetAddOnCPUUsage). Verified present before
-- profiling can start; we cache the reference so the hot path in Core:Tick can
-- read it as a global.
-- ---------------------------------------------------------------------------
local function nowMs()
  return debugprofilestop and debugprofilestop() or 0
end

-- ---------------------------------------------------------------------------
-- Stats accumulation. Called from Core:Tick only while active.
-- ---------------------------------------------------------------------------
function Profiler:Record(name, dt, kb)
  local s = self.stats[name]
  if not s then
    s = { ms = 0, calls = 0, max = 0, kb = 0 }
    self.stats[name] = s
  end
  s.ms = s.ms + dt
  s.calls = s.calls + 1
  if dt > s.max then s.max = dt end
  -- A GC step inside the window makes the heap delta negative; that is the
  -- collector's work, not this module's, so it does not count against it.
  if kb and kb > 0 then s.kb = s.kb + kb end
end

function Profiler:RecordCore(dt, kb)
  self:Record(CORE_KEY, dt, kb)
end

-- Scoped measurement for the event-driven scans (Auras, Cooldowns): the
-- caller reads Nock._prof once, marks, works, and files the result under its
-- own name. Two numbers on the stack, nothing allocated.
function Profiler:Mark()
  return debugprofilestop(), collectgarbage("count")
end

function Profiler:Done(name, t0, k0)
  self:Record(name, debugprofilestop() - t0, collectgarbage("count") - k0)
end

-- The client's own per-addon figure (KB). UpdateAddOnMemoryUsage is a walk
-- over every addon, so it is only ever called from a report.
local function addonKb()
  if UpdateAddOnMemoryUsage and GetAddOnMemoryUsage then
    UpdateAddOnMemoryUsage()
    return GetAddOnMemoryUsage("Nock") or 0
  end
  return collectgarbage("count")
end

function Profiler:CountTick(totalDt)
  self.tickCount = self.tickCount + 1
  self.totalTickMs = self.totalTickMs + totalDt
end

-- ---------------------------------------------------------------------------
-- Nameplate sampler (tests the "client changed nameplate logic" hypothesis).
-- ---------------------------------------------------------------------------
function Profiler:Sample()
  local n = 0
  if C_NamePlate and C_NamePlate.GetNamePlates then
    local plates = C_NamePlate.GetNamePlates()
    if plates then n = #plates end
  end
  self.plateNow = n
  if n > self.plateMax then self.plateMax = n end
end

-- ---------------------------------------------------------------------------
-- Event-rate counters. Registered only while active so there is no cost when
-- stopped (CLEU fires hundreds/sec on a boss — we must not sit on it idle).
-- ---------------------------------------------------------------------------
function Profiler:EnsureEventFrame()
  if self.evtFrame then return self.evtFrame end
  local f = CreateFrame("Frame")
  f:SetScript("OnEvent", function(_, event)
    if event == "UNIT_AURA" then
      self.aura = self.aura + 1
    else
      self.cleu = self.cleu + 1
    end
  end)
  self.evtFrame = f
  return f
end

-- ---------------------------------------------------------------------------
-- The panel's numbers. CPU per addon exists only while the client's
-- `scriptProfile` CVar is on (a /reload applies it); memory always does.
-- Both come as cumulative counters, so a rate is a delta over the interval.
-- ---------------------------------------------------------------------------
local function cpuProfilingOn()
  return GetCVar and GetCVar("scriptProfile") == "1"
end

local function numAddOns()
  if C_AddOns and C_AddOns.GetNumAddOns then return C_AddOns.GetNumAddOns() end
  if GetNumAddOns then return GetNumAddOns() end
  return 0
end

-- Per-addon memory: UpdateAddOnMemoryUsage runs a FULL garbage-collection
-- pass over the whole Lua heap (hundreds of MB with a normal addon set) --
-- a visible hitch per call, so it is never on a timer: the panel reads it on
-- Capture start/stop and when the panel is clicked. -> allKb, nockKb
local function addonMemory()
  if UpdateAddOnMemoryUsage and GetAddOnMemoryUsage then
    UpdateAddOnMemoryUsage()
    local allKb = 0
    for i = 1, numAddOns() do allKb = allKb + (GetAddOnMemoryUsage(i) or 0) end
    return allKb, GetAddOnMemoryUsage("Nock") or 0
  end
  return collectgarbage("count"), 0
end

-- Per-addon CPU counters (a snapshot, cheap; the cost of scriptProfile itself
-- is paid on every addon call while the CVar is on). -> allCpuMs, nockCpuMs,
-- or nil, nil without the CVar.
local function addonCpu()
  if cpuProfilingOn() and UpdateAddOnCPUUsage and GetAddOnCPUUsage then
    UpdateAddOnCPUUsage()
    local allCpu = 0
    for i = 1, numAddOns() do allCpu = allCpu + (GetAddOnCPUUsage(i) or 0) end
    return allCpu, GetAddOnCPUUsage("Nock") or 0
  end
  return nil, nil
end

-- Pure: cumulative CPU ms at two samples `dt` seconds apart -> ms per second
-- for all addons and for Nock; nil where the counters are absent.
function Profiler.Rates(prevAll, prevNock, curAll, curNock, dt)
  if not (dt and dt > 0) then return nil, nil end
  local all  = (prevAll  and curAll)  and math.max(0, curAll  - prevAll)  / dt or nil
  local nock = (prevNock and curNock) and math.max(0, curNock - prevNock) / dt or nil
  return all, nock
end

-- ---------------------------------------------------------------------------
-- Window helpers.
-- ---------------------------------------------------------------------------
local function windowSec(self)
  local w = GetTime() - self.windowStart
  return (w > 0.001) and w or 0.001
end

-- Sorted array of { name, ms, calls, max, kb } by the given field desc.
local function sortedStats(self, field)
  field = field or "ms"
  local out = {}
  for name, s in pairs(self.stats) do
    out[#out + 1] = { name = name, ms = s.ms, calls = s.calls, max = s.max, kb = s.kb or 0 }
  end
  table.sort(out, function(a, b) return a[field] > b[field] end)
  return out
end

local function totalKb(self)
  local t = 0
  for _, s in pairs(self.stats) do t = t + (s.kb or 0) end
  return t
end

-- ---------------------------------------------------------------------------
-- Chat report.
-- ---------------------------------------------------------------------------
-- The report is evidence the user pastes back, so it opens in the copybox
-- (project rule: chat cannot be copied); one chat line says it did.
function Profiler:BuildReport()
  local w = windowSec(self)
  local tps = self.tickCount / w
  local msPerSec = self.totalTickMs / w
  local cap = (Nock.db and Nock.db.profile and Nock.db.profile.perfTickHz) or 0
  local memNow = addonKb()
  local lines = {}
  local function add(fmt, ...) lines[#lines + 1] = fmt:format(...) end
  add("== Nock profile: %.1fs  ticks/s %.0f (%s)  addon %.2f ms/s  ~%.1f%% core ==",
    w, tps, (cap > 0) and ("cap " .. cap) or "uncapped", msPerSec, msPerSec / 10)
  add("   plates %d (max %d)   CLEU/s %.0f   aura/s %.0f",
    self.plateNow, self.plateMax, self.cleu / w, self.aura / w)
  add("   memory: Nock %.1f MB now (%.1f MB at start, %+.1f MB)   measured garbage %.1f KB/s   Lua heap %.1f MB",
    memNow / 1024, (self.memStart or 0) / 1024, (memNow - (self.memStart or 0)) / 1024,
    totalKb(self) / w, collectgarbage("count") / 1024)
  add("   module              ms/call   %%tick    maxms    ms/s    KB/s   calls/s")
  local total = (self.totalTickMs > 0) and self.totalTickMs or 1
  for _, e in ipairs(sortedStats(self, "kb")) do
    local avg = (e.calls > 0) and (e.ms / e.calls) or 0
    add("   %-18s  %6.3f   %5.1f%%   %6.3f  %6.2f  %6.1f  %7.1f",
      e.name, avg, e.ms / total * 100, e.max, e.ms / w, e.kb / w, e.calls / w)
  end
  add("   (sorted by KB/s: the module whose garbage fills the addon's memory figure between GC cycles)")
  return table.concat(lines, "\n")
end

function Profiler:PrintReport()
  local text = self:BuildReport()
  if Nock.UI and Nock.UI.ShowCopyBox then
    Nock.UI.ShowCopyBox(text)
    self:Print(("profile report: %.1fs window, %.1f KB/s of garbage measured -- see the copy box."):format(
      windowSec(self), totalKb(self) / windowSec(self)))
  else
    for line in text:gmatch("[^\n]+") do self:Print(line) end
  end
end

-- ---------------------------------------------------------------------------
-- Live overlay.
-- ---------------------------------------------------------------------------
function Profiler:EnsureOverlay()
  if self.overlay then return self.overlay end
  local f = CreateFrame("Frame", "NockProfilerOverlay", UIParent, "BackdropTemplate")
  f:SetSize(196, 74)
  f:SetBackdrop({
    bgFile   = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
  })
  f:SetBackdropColor(0, 0, 0, 0.8)
  f:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
  f:SetFrameStrata("HIGH")
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(fr) fr._dragged = true; fr:StartMoving() end)
  f:SetScript("OnDragStop", function(fr)
    fr:StopMovingOrSizing()
    local point, _, relPoint, x, y = fr:GetPoint()
    local p = Nock.db and Nock.db.profile
    if p then p.profilerOverlayPos = { point = point, relPoint = relPoint, x = x, y = y } end
  end)
  f:SetScript("OnEnter", function(fr)
    if not GameTooltip then return end
    GameTooltip:SetOwner(fr, "ANCHOR_BOTTOMLEFT")
    GameTooltip:AddLine("Nock performance", 1, 0.82, 0)
    GameTooltip:AddLine("mem: Lua heap live; the per-addon split is refreshed on a click here and at Capture (the client's per-addon read is a full GC pass -- a hitch -- so it is never on a timer).", 0.9, 0.9, 0.9, true)
    if cpuProfilingOn() then
      GameTooltip:AddLine("cpu: script time per second, all addons vs Nock.", 0.9, 0.9, 0.9, true)
    else
      GameTooltip:AddLine("cpu: needs the client's scriptProfile CVar -- /nock profile cpu on, then /reload.", 1, 0.6, 0.2, true)
    end
    GameTooltip:AddLine("Capture: records what Nock allocates and spends per module (up to 60 s), then opens the report.", 0.9, 0.9, 0.9, true)
    GameTooltip:Show()
  end)
  f:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  -- A click (not a drag) refreshes the per-addon memory split on demand.
  f:SetScript("OnMouseUp", function(fr, button)
    if button == "LeftButton" and not fr._dragged then Profiler:RefreshMemory() end
    fr._dragged = nil
  end)

  local function row(y)
    local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", 8, y)
    fs:SetPoint("RIGHT", -8, 0)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return fs
  end
  f.rowAll  = row(-7)
  f.rowNock = row(-21)

  -- Capture: the shell's button when the skin is loaded, the client's otherwise.
  local Skin = Nock.UI and Nock.UI.Skin
  local b
  if Skin and Skin.Button then
    b = Skin.Button(f, "Capture", "ghost", 180, 20)
  else
    b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    b:SetSize(180, 20)
    b:SetText("Capture")
    b.text = b:GetFontString()
  end
  b:SetPoint("BOTTOM", f, "BOTTOM", 0, 7)
  b:SetScript("OnClick", function() Profiler:ToggleCapture() end)
  f.capture = b

  local p = Nock.db and Nock.db.profile
  local pos = p and p.profilerOverlayPos
  if pos then
    f:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
  else
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -220)
  end
  self.overlay = f
  return f
end

local function setButtonText(b, text)
  if b._text == text then return end
  b._text = text
  local Skin = Nock.UI and Nock.UI.Skin
  if Skin and Skin.SetButtonText and b.kind then Skin.SetButtonText(b, text, 180)
  elseif b.SetText then b:SetText(text) end
end

local function fmtMs(ms)
  if ms == nil then return "  --  " end
  return ("%5.1f"):format(ms)
end

-- The on-demand memory read (the expensive one): Capture start/stop and a
-- click on the panel.
function Profiler:RefreshMemory()
  self._memAll, self._memNock = addonMemory()
  self._memAt = GetTime()
  self:UpdateOverlay()
end

function Profiler:UpdateOverlay()
  local f = self.overlay
  if not f or not f:IsShown() then return end
  local now = GetTime()
  local allCpu, nockCpu = addonCpu()
  local allRate, nockRate = Profiler.Rates(self._cpuAll, self._cpuNock, allCpu, nockCpu,
                                           self._cpuAt and (now - self._cpuAt) or nil)
  self._cpuAll, self._cpuNock, self._cpuAt = allCpu, nockCpu, now
  -- While a capture runs the tick profiler knows Nock's own cost exactly,
  -- CVar or not; the panel shows it from the capture's window.
  if self.active then
    local w = windowSec(self)
    nockRate = self.totalTickMs / w
  end
  if not self._memAt then self:RefreshMemory(); return end
  -- The All row is the live Lua heap (O(1)); the per-addon split is the last
  -- on-demand read, aged so a stale Nock figure is not mistaken for live.
  local age = now - self._memAt
  local nockMem = (age < 2) and ("%6.1f MB"):format(self._memNock / 1024)
                  or ("%6.1f MB (%ds ago)"):format(self._memNock / 1024, age)
  f.rowAll:SetText(("|cffa0a0a0All |r  cpu %s ms/s   heap %6.1f MB"):format(fmtMs(allRate), collectgarbage("count") / 1024))
  f.rowNock:SetText(("|cffffd100Nock|r  cpu %s ms/s   mem %s"):format(fmtMs(nockRate), nockMem))
  if self.active then
    setButtonText(f.capture, ("Stop  %ds"):format(math.floor(now - self.windowStart + 0.5)))
  else
    setButtonText(f.capture, "Capture")
  end
end

-- The panel's button: a capture is a profile window with a stop clock. Stop
-- (or the clock) opens the report in the copybox.
function Profiler:ToggleCapture()
  if self.active then
    self:Stop()
    return
  end
  self:Start()
  if self.active then
    self._captureTimer = self:ScheduleTimer("CaptureTimeout", CAPTURE_MAX)
    self:RefreshMemory()
  end
end

function Profiler:CaptureTimeout()
  self._captureTimer = nil
  if self.active then self:Stop() end
end

-- ---------------------------------------------------------------------------
-- Lifecycle.
-- ---------------------------------------------------------------------------
function Profiler:ResetStats()
  self.stats = {}
  self.tickCount = 0
  self.totalTickMs = 0
  self.cleu = 0
  self.aura = 0
  self.plateNow = 0
  self.plateMax = 0
  self.windowStart = GetTime()
  self.memStart = addonKb()
end

function Profiler:Start()
  if not debugprofilestop then
    self:Print("profiler unavailable: debugprofilestop() is nil on this client.")
    return
  end
  self:ResetStats()
  self:EnsureEventFrame()
  self.evtFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
  self.evtFrame:RegisterEvent("UNIT_AURA")
  if not self.sampleTimer then
    self.sampleTimer = self:ScheduleRepeatingTimer("Sample", SAMPLE_INTERVAL)
  end
  self.active = true
  Nock._prof = self   -- arm the Core:Tick hooks
  self:Print(("profiling ON (Nock %.1f MB) — /nock profile report to read, stop to end, show for overlay."):format(
    (self.memStart or 0) / 1024))
end

function Profiler:Stop()
  if not self.active then
    self:Print("profiling was not running.")
    return
  end
  Nock._prof = nil
  self.active = false
  if self.evtFrame then self.evtFrame:UnregisterAllEvents() end
  if self.sampleTimer then
    self:CancelTimer(self.sampleTimer)
    self.sampleTimer = nil
  end
  if self._captureTimer then
    self:CancelTimer(self._captureTimer)
    self._captureTimer = nil
  end
  self:PrintReport()
  self:Print("profiling OFF.")
  if self.overlay and self.overlay:IsShown() then self:RefreshMemory() end
end

function Profiler:ShowOverlay(show)
  local f = self:EnsureOverlay()
  if show then
    f:Show()
    if not self.overlayTimer then
      self.overlayTimer = self:ScheduleRepeatingTimer("UpdateOverlay", OVERLAY_INTERVAL)
    end
    self:UpdateOverlay()
  else
    f:Hide()
    if self.overlayTimer then
      self:CancelTimer(self.overlayTimer)
      self.overlayTimer = nil
    end
  end
  local p = Nock.db and Nock.db.profile
  if p then p.profilerOverlayShown = show and true or false end
end

-- The two staged fixes are toggled live from here so you can A/B them mid-raid
-- without an Options round-trip.
function Profiler:CmdTick(arg)
  local p = Nock.db and Nock.db.profile
  if not p then return end
  local hz = tonumber(arg)
  if hz == nil then
    self:Print(("tick throttle: %s. Usage: /nock profile tick <hz>  (0 = uncapped, 30 recommended)"):format(
      (p.perfTickHz or 0) > 0 and ("cap " .. p.perfTickHz .. " Hz") or "uncapped"))
    return
  end
  if hz < 0 then hz = 0 end
  if hz > 120 then hz = 120 end
  p.perfTickHz = hz
  self:Print(("tick throttle → %s (takes effect immediately)."):format(
    hz > 0 and ("cap " .. hz .. " Hz") or "uncapped (0)"))
end

function Profiler:CmdScans(arg)
  local p = Nock.db and Nock.db.profile
  if not p then return end
  if arg == "on" then
    p.perfThrottleScans = true
  elseif arg == "off" then
    p.perfThrottleScans = false
  else
    p.perfThrottleScans = not p.perfThrottleScans
  end
  self:Print(("scan throttle → %s (Warnings / TotemTracker / PetStatus / buff+debuff trackers)."):format(
    p.perfThrottleScans and "ON (~10 Hz)" or "OFF (per-frame, old behavior)"))
end

-- The client's per-addon CPU accounting (the panel's cpu cells). A CVar, so
-- it survives the session and needs a /reload to start counting.
function Profiler:CmdCpu(arg)
  if not (SetCVar and GetCVar) then return end
  if arg == "on" then
    SetCVar("scriptProfile", "1")
    self:Print("addon CPU accounting ON (scriptProfile=1) -- /reload to start counting. It taxes EVERY addon call (a real FPS cost); /nock profile cpu off and /reload when done.")
  elseif arg == "off" then
    SetCVar("scriptProfile", "0")
    self:Print("addon CPU accounting OFF -- /reload to apply.")
  else
    self:Print(("addon CPU accounting is %s. Usage: /nock profile cpu on|off (then /reload)."):format(
      cpuProfilingOn() and "ON" or "OFF"))
  end
end

-- Dispatched from Core:HandleSlashCommand — receives everything after "profile".
function Profiler:Command(msg)
  local sub, arg = (msg or ""):match("^(%S*)%s*(.-)$")
  if sub == "" or sub == "start" then
    self:Start()
  elseif sub == "stop" then
    self:Stop()
  elseif sub == "report" then
    if not self.active and self.tickCount == 0 then
      self:Print("no data — /nock profile start first.")
    else
      self:PrintReport()
    end
  elseif sub == "reset" then
    self:ResetStats()
    self:Print("profile stats reset.")
  elseif sub == "show" then
    self:ShowOverlay(true)
  elseif sub == "hide" then
    self:ShowOverlay(false)
  elseif sub == "tick" then
    self:CmdTick(arg)
  elseif sub == "scans" or sub == "trackers" then   -- "trackers" kept as an alias
    self:CmdScans(arg)
  elseif sub == "cpu" then
    self:CmdCpu(arg)
  elseif sub == "capture" then
    self:ToggleCapture()
  else
    self:Print(("profile: unknown '%s' — try start|stop|report|reset|show|hide|capture|cpu on/off|tick <hz>|scans on/off"):format(sub))
  end
end

function Profiler:OnEnable()
  self.stats = self.stats or {}
  self.windowStart = GetTime()
  local p = Nock.db and Nock.db.profile
  if p and p.profilerOverlayShown then
    self:ShowOverlay(true)
  end
end
