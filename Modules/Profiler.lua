-- Modules/Profiler.lua
-- Opt-in performance profiler: per-module tick timing, tick-rate, event-rate,
-- and nameplate-count sampling. Zero overhead when stopped (Nock._prof is nil,
-- so Core:Tick never touches it and no events are registered). Drives the
-- /nock profile slash family and an optional live on-screen overlay.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local Profiler = Nock:NewModule("Profiler", "AceTimer-3.0", "AceConsole-3.0")

local CORE_KEY       = "(core-body)"
local SAMPLE_INTERVAL = 0.25   -- nameplate-count sampler
local OVERLAY_INTERVAL = 0.5   -- overlay refresh (not per-frame)

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
function Profiler:Record(name, dt)
  local s = self.stats[name]
  if not s then
    s = { ms = 0, calls = 0, max = 0 }
    self.stats[name] = s
  end
  s.ms = s.ms + dt
  s.calls = s.calls + 1
  if dt > s.max then s.max = dt end
end

function Profiler:RecordCore(dt)
  self:Record(CORE_KEY, dt)
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
-- Window helpers.
-- ---------------------------------------------------------------------------
local function windowSec(self)
  local w = GetTime() - self.windowStart
  return (w > 0.001) and w or 0.001
end

-- Sorted array of { name, ms, calls, max } by total ms desc. Reused each call.
local function sortedStats(self)
  local out = {}
  for name, s in pairs(self.stats) do
    out[#out + 1] = { name = name, ms = s.ms, calls = s.calls, max = s.max }
  end
  table.sort(out, function(a, b) return a.ms > b.ms end)
  return out
end

-- ---------------------------------------------------------------------------
-- Chat report.
-- ---------------------------------------------------------------------------
function Profiler:PrintReport()
  local w = windowSec(self)
  local tps = self.tickCount / w
  local msPerSec = self.totalTickMs / w
  local cap = (Nock.db and Nock.db.profile and Nock.db.profile.perfTickHz) or 0
  self:Print(("== profile: %.1fs  ticks/s %.0f (%s)  addon %.2f ms/s  ~%.1f%% core =="):format(
    w, tps, (cap > 0) and ("cap " .. cap) or "uncapped", msPerSec, msPerSec / 10))
  self:Print(("   plates %d (max %d)   CLEU/s %.0f   aura/s %.0f"):format(
    self.plateNow, self.plateMax, self.cleu / w, self.aura / w))
  self:Print("   module            ms/tick   %tick    maxms   ms/s")
  local total = (self.totalTickMs > 0) and self.totalTickMs or 1
  for _, e in ipairs(sortedStats(self)) do
    local avg = (e.calls > 0) and (e.ms / e.calls) or 0
    self:Print(("   %-16s  %6.3f   %5.1f%%   %6.3f  %5.2f"):format(
      e.name, avg, e.ms / total * 100, e.max, e.ms / w))
  end
end

-- ---------------------------------------------------------------------------
-- Live overlay.
-- ---------------------------------------------------------------------------
function Profiler:EnsureOverlay()
  if self.overlay then return self.overlay end
  local f = CreateFrame("Frame", "NockProfilerOverlay", UIParent, "BackdropTemplate")
  f:SetSize(230, 150)
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
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(fr)
    fr:StopMovingOrSizing()
    local point, _, relPoint, x, y = fr:GetPoint()
    local p = Nock.db and Nock.db.profile
    if p then p.profilerOverlayPos = { point = point, relPoint = relPoint, x = x, y = y } end
  end)

  local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetPoint("TOPLEFT", 8, -8)
  fs:SetPoint("BOTTOMRIGHT", -8, 8)
  fs:SetJustifyH("LEFT")
  fs:SetJustifyV("TOP")
  f.text = fs

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

function Profiler:UpdateOverlay()
  local f = self.overlay
  if not f or not f:IsShown() then return end
  if not self.active then
    f.text:SetText("|cffffd100Nock Profiler|r  [idle]\n\n/nock profile start\nto begin measuring.")
    return
  end
  local w = windowSec(self)
  local tps = self.tickCount / w
  local msPerSec = self.totalTickMs / w
  local cap = (Nock.db and Nock.db.profile and Nock.db.profile.perfTickHz) or 0
  local lines = {
    "|cffffd100Nock Profiler|r  [live]",
    -- Uncapped is the recommended state: the tick also drives bar animation, so
    -- capping it reads as stutter. Cap is the flagged/unusual case, not uncapped.
    ("ticks/s   %.0f   %s"):format(tps, (cap > 0) and ("|cffffd100(cap " .. cap .. ")|r") or "|cff808080(uncapped)|r"),
    ("addon ms/s %.1f   ~%.1f%% core"):format(msPerSec, msPerSec / 10),
    ("plates     %d   (max %d)"):format(self.plateNow, self.plateMax),
    ("CLEU/s    %.0f   aura/s %.0f"):format(self.cleu / w, self.aura / w),
    "|cff808080-- top (ms/s) --|r",
  }
  local sorted = sortedStats(self)
  for i = 1, 3 do
    local e = sorted[i]
    if e then
      lines[#lines + 1] = ("%-14s %.2f"):format(e.name, e.ms / w)
    end
  end
  f.text:SetText(table.concat(lines, "\n"))
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
  self:Print("profiling ON — /nock profile report to read, stop to end, show for overlay.")
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
  self:PrintReport()
  self:Print("profiling OFF.")
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
  else
    self:Print(("profile: unknown '%s' — try start|stop|report|reset|show|hide|tick <hz>|scans on/off"):format(sub))
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
