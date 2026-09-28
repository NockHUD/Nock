-- Forever/CameraFlip.lua
-- The weave camera flip: SetView + mouselook turns the character away on the melee hit and back for the shot, the camera never moves.

-- After the SoD "Melee Weave Smart Camera Flip" WeakAura (wago tYbtnSVt4).
-- Two macro lines drive it:
--   Raptor macro, last line:      /run NockCamFlip()   turns away on the next melee hit
--   Auto Shot spam, last line:    /run NockCamFace()   turns back; idempotent
-- Profile: cameraFlipEnabled (off by default) and cameraFlipGate (the range
-- cues' solo/party/raid ladder, raid by default): a gated-out weave never
-- arms a turn, so the macro lines can stay in place everywhere.
-- The recipe, every step settled on the dummy and in recordings 2026-09-28
-- (all camera calls are plain in combat here, nothing was ever blocked):
--   * view 1 = a camera in front of the character looking at its face,
--     saved by the setup window at the played zoom and tilt (the only
--     writer of it; Forever/CameraSetupView.lua is the window).
--   * a turn = SetView(1), next frame MouselookStart + MouselookStop. The
--     snap lands at the camera update after the pair, needs the camera to
--     have arrived (cameraViewBlendStyle 2, and one frame: same-frame leaves
--     the camera behind the character, world flipped) and a fresh off->on
--     mouselook edge (a held RMB is stopped first). A programmatic
--     MouselookStart only snaps after a SetView; a hardware RMB always does.
--   * out: nothing after the snap but a one-frame zoom correction. The
--     camera stays on the face side: world view unchanged, the character
--     runs toward the camera, exactly the aura's gif. Any view or mouselook
--     call here put the camera behind (world flipped).
--   * back: the same turn (view 1 relative to the turned-away character is
--     where the camera already stands, so no flash), then one MouselookStart
--     a frame after the snap puts the camera behind, released a frame later
--     unless RMB is held. Restoring it in the snap frame un-turned.
--   * the one drawn frame at the 180 view on the way out is the floor; a
--     black cover for that frame read worse (user, 2026-09-28).
--     FlipCameraYaw only rotates the picture (the next RMB snaps to the
--     stale yaw): never use it.
-- Commands (/nock camera ..., also /nock probe camera ...): none = the report
--   copybox | setup [step] | show (SetView 1 alone) | out | back (a turn by
--   hand, no target or gate) | delay <out> [<back>] (s, 0 = next frame) |
--   debug on|off | reset (clear the latch). delay and debug are runtime only.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local CameraFlip = Nock:NewModule("CameraFlip", "AceEvent-3.0")
Nock.CameraFlip = CameraFlip

local CAMERA_APIS = { "SetView", "SaveView", "MouselookStart", "MouselookStop", "IsMouselooking", "IsMouseButtonDown",
  "GetPlayerFacing", "GetCameraZoom", "CameraZoomOut", "RunNextFrame", "UnitCanAttack" }
local CAMERA_CVARS = { "cameraViewBlendStyle", "cameraSmoothStyle" }
local CAMERA_TRIAL_MAX, CAMERA_BLOCKED_MAX = 24, 20
local CAMERA_COOLDOWN = 0.5        -- s between two turns
local CAMERA_DELAY_DEFAULT = 0       -- s from SetView(1) to the pair, 0 = next frame (out)
local CAMERA_DELAY_BACK_DEFAULT = 0  -- same for the return
local CAMERA_ARM_WINDOW = 1.5      -- s a macro-armed turn waits for the melee hit
local CAMERA_SETUP_TOL = 2.0       -- degrees either side of 180

-- Pure: the profile switch (off unless set).
function CameraFlip.Enabled(p)
  return p ~= nil and p.cameraFlipEnabled == true
end

-- Pure: may a macro turn fire in this group context ("solo" | "party" |
-- "raid")? The range cues' ladder; an unknown gate reads as raid.
function CameraFlip.Allowed(p, ctx)
  if not CameraFlip.Enabled(p) then return false end
  local RC = Nock.GetModule and Nock:GetModule("RangeCues", true)
  local gate = p.cameraFlipGate or "raid"
  if RC and RC.GateAllows then return RC.GateAllows(gate, ctx or "solo") end
  return gate == "solo"
end

function CameraFlip:OnEnable()
  -- Every blocked or forbidden call, with the function name: the report
  -- reads protection status off this ring.
  self:RegisterEvent("ADDON_ACTION_BLOCKED", "OnBlocked")
  self:RegisterEvent("ADDON_ACTION_FORBIDDEN", "OnBlocked")
end

-- Pure: signed degrees from facing a to facing b (radians), in (-180, 180].
function CameraFlip.FacingDelta(a, b)
  if type(a) ~= "number" or type(b) ~= "number" then return nil end
  local d = ((b - a) * 180 / math.pi) % 360
  if d > 180 then d = d - 360 end
  return d
end

-- Pure: the copybox text. d = { apis = {{name, present}}, cvars = {{name, value}},
--   facing, moving, mouselooking, combat, restrictions = {{name, state}},
--   flipped, armed, delay, trials = {{ t, kind, combat, f0, f1, f2, t1, t2,
--   ml0, ml1, ml2, z0, z1, z2, errs = {} }}, blocked = {{ t, ev, who, fn }} }
function CameraFlip.CameraReport(d)
  local L = {}
  local function row(s) L[#L + 1] = s end
  local parts = {}
  for _, a in ipairs(d.apis or {}) do parts[#parts + 1] = a[1] .. (a[2] and "" or "=MISSING") end
  row("apis: " .. table.concat(parts, "  "))
  parts = {}
  for _, c in ipairs(d.cvars or {}) do parts[#parts + 1] = c[1] .. "=" .. tostring(c[2]) end
  row("cvars: " .. table.concat(parts, "  "))
  parts = {}
  for _, r in ipairs(d.restrictions or {}) do parts[#parts + 1] = r[1] .. "=" .. tostring(r[2]) end
  row("restrictions: " .. table.concat(parts, "  "))
  row(("facing now: %s  moving: %s  mouselooking: %s  combat: %s"):format(tostring(d.facing), tostring(d.moving),
    tostring(d.mouselooking), tostring(d.combat)))
  row(("flipped: %s  armed: %s  delay: %s  back: %s"):format(tostring(d.flipped == true), tostring(d.armed == true),
    tostring(d.delay or CAMERA_DELAY_DEFAULT), tostring(d.delayBack or CAMERA_DELAY_BACK_DEFAULT)))
  row("")
  row("turns (t, kind, combat, facing before / after the calls / frame after, step degrees, total turned,")
  row("       ms to each stamp, IsMouselooking at each stamp, zoom at each stamp, errors, blocked calls):")
  for _, T in ipairs(d.trials or {}) do
    local delta = CameraFlip.FacingDelta(T.f0, T.f2 or T.f1)
    local s1, s2 = CameraFlip.FacingDelta(T.f0, T.f1), CameraFlip.FacingDelta(T.f1, T.f2)
    local blocked = {}
    for _, b in ipairs(d.blocked or {}) do
      if b.t >= T.t - 0.05 and b.t <= T.t + 0.5 then blocked[#blocked + 1] = tostring(b.fn) end
    end
    local function ms(t) return t and ("%.0f"):format((t - T.t) * 1000) or "?" end
    local function z(v) return type(v) == "number" and ("%.1f"):format(v) or "?" end
    row(("  %.2f  %-4s  combat %-5s  %s / %s / %s  steps %s %s  turned %s  ms %s %s  ml %s %s %s  zoom %s %s %s  errs %s  blocked %s"):format(
      T.t, tostring(T.kind), tostring(T.combat),
      tostring(T.f0), tostring(T.f1), tostring(T.f2),
      s1 and ("%.1f"):format(s1) or "?", s2 and ("%.1f"):format(s2) or "?",
      delta and ("%.1f"):format(delta) or "?", ms(T.t1), ms(T.t2),
      tostring(T.ml0), tostring(T.ml1), tostring(T.ml2), z(T.z0), z(T.z1), z(T.z2),
      (T.errs and #T.errs > 0) and table.concat(T.errs, "; ") or "none",
      #blocked > 0 and table.concat(blocked, ",") or "none"))
  end
  row("")
  row("ADDON_ACTION_BLOCKED / FORBIDDEN seen (t, event, addon, function):")
  for _, b in ipairs(d.blocked or {}) do
    row(("  %.2f  %s  %s  %s"):format(b.t, tostring(b.ev), tostring(b.who), tostring(b.fn)))
  end
  return table.concat(L, "\n")
end

function CameraFlip:OnBlocked(event, who, fn)
  local B = self._blocked
  if not B then B = {}; self._blocked = B end
  B[#B + 1] = { t = GetTime(), ev = event, who = who, fn = fn }
  if #B > CAMERA_BLOCKED_MAX then table.remove(B, 1) end
end

local function cameraFacing()
  local f = _G.GetPlayerFacing and Nock.Flavor.Plain(_G.GetPlayerFacing())
  return type(f) == "number" and f or nil
end

local function cameraZoom() return _G.GetCameraZoom and _G.GetCameraZoom() end

local function cameraNextFrame(fn)
  if _G.RunNextFrame then _G.RunNextFrame(fn) else C_Timer.After(0, fn) end
end

local function cameraCall(errs, name, ...)
  local f = _G[name]
  if not f then errs[#errs + 1] = name .. ": missing"; return end
  local ok, err = pcall(f, ...)
  if not ok then errs[#errs + 1] = name .. ": " .. tostring(err) end
end

local function cameraMouselooking()
  return _G.IsMouselooking and _G.IsMouselooking() == true or false
end

local function cameraButtonDown(name)
  return _G.IsMouseButtonDown and _G.IsMouseButtonDown(name) == true
end

local function cameraGetCVar(name)
  local get = (_G.C_CVar and _G.C_CVar.GetCVar) or _G.GetCVar
  return get and get(name)
end

local function cameraSetCVar(name, value)
  local set = (_G.C_CVar and _G.C_CVar.SetCVar) or _G.SetCVar
  if set then set(name, value) end
end

local function camSay(self, msg) if self._cameraDebug then Nock:Print("cam: " .. msg) end end

function CameraFlip:CameraSay(T)
  local delta = CameraFlip.FacingDelta(T.f0, T.f2 or T.f1)
  local blocked = 0
  for _, b in ipairs(self._blocked or {}) do if b.t >= T.t - 0.05 then blocked = blocked + 1 end end
  camSay(self, ("%s: turned %s deg  errors %d  blocked calls %d"):format(tostring(T.kind),
    delta and ("%.1f"):format(delta) or "?", T.errs and #T.errs or 0, blocked))
end

-- One turn; `back` is the return. Records a report row.
function CameraFlip:CameraTurn(back)
  local T = { t = GetTime(), kind = back and "back" or "out", errs = {},
    combat = Nock.Flavor.Plain(_G.InCombatLockdown and _G.InCombatLockdown()) == true,
    f0 = cameraFacing(), ml0 = cameraMouselooking(), z0 = cameraZoom() }
  local R = self._cameraTrials
  if not R then R = {}; self._cameraTrials = R end
  R[#R + 1] = T
  if #R > CAMERA_TRIAL_MAX then table.remove(R, 1) end
  local errs = T.errs
  local function stamp1() T.f1, T.t1, T.ml1, T.z1 = cameraFacing(), GetTime(), cameraMouselooking(), cameraZoom() end
  local function finish() T.f2, T.t2, T.ml2, T.z2 = cameraFacing(), GetTime(), cameraMouselooking(), cameraZoom(); self:CameraSay(T) end
  -- Return only: the camera sits on the face side after the snap; one
  -- mouselook a frame later puts it behind, kept if RMB is held.
  local function realign()
    cameraCall(errs, "MouselookStart")
    if cameraButtonDown("RightButton") then finish(); return end
    cameraNextFrame(function() cameraCall(errs, "MouselookStop"); finish() end)
  end
  -- Out only: view 1 carries the distance setup saved; jump to the live
  -- one (cameraZoomSpeed is 20 yd/s, a visible crawl: boosted for this one
  -- frame). Never touches view 1 itself.
  local function zoomFix()
    local zn = cameraZoom()
    if type(T.z0) == "number" and type(zn) == "number" and math.abs(T.z0 - zn) > 0.05 then
      local speed = cameraGetCVar("cameraZoomSpeed")
      cameraSetCVar("cameraZoomSpeed", "1000")
      if T.z0 > zn then cameraCall(errs, "CameraZoomOut", T.z0 - zn) else cameraCall(errs, "CameraZoomIn", zn - T.z0) end
      cameraNextFrame(function()
        if speed then cameraSetCVar("cameraZoomSpeed", speed) end
        finish()
      end)
    else
      finish()
    end
  end
  local function snap()
    cameraCall(errs, "MouselookStart"); cameraCall(errs, "MouselookStop")
    stamp1()
    cameraNextFrame(back and realign or zoomFix)
  end
  local function go()
    cameraCall(errs, "SetView", 1)
    local delay = back and (self._cameraDelayBack or CAMERA_DELAY_BACK_DEFAULT) or (self._cameraDelay or CAMERA_DELAY_DEFAULT)
    C_Timer.After(delay, snap)
  end
  -- A held RMB means mouselook is already on: no edge for the snap.
  if T.ml0 then cameraCall(errs, "MouselookStop"); cameraNextFrame(go) else go() end
end

-- The guarded turn-away: once per cooldown, never twice without a return
-- between, and (from a macro) only with an attackable target.
function CameraFlip:CamDoFlip(needTarget)
  local now = GetTime()
  if self._cameraFlipped then camSay(self, "turn refused: already turned away (NockCamFace first)"); return false end
  if now < (self._cameraNext or 0) then camSay(self, "turn refused: cooldown"); return false end
  if needTarget and Nock.Flavor.Plain(_G.UnitCanAttack and _G.UnitCanAttack("player", "target")) ~= true then
    camSay(self, "turn refused: no attackable target"); return false
  end
  self._cameraNext = now + CAMERA_COOLDOWN
  self._cameraFlipped = true
  self:CameraTurn(false)
  return true
end

-- The return. No-op unless a turn is outstanding, so a spammed macro is fine.
function CameraFlip:CamFace()
  if not self._cameraFlipped then return false end
  self._cameraFlipped = false
  self:CameraTurn(true)
  return true
end

-- Macro hook: arm a turn for the next MainHand hit (within CAMERA_ARM_WINDOW),
-- so it can never land before the swing; `NockCamFlip(true)` turns at once.
function CameraFlip:CamFlipRequest(now)
  local p = Nock.db and Nock.db.profile
  local RC = Nock:GetModule("RangeCues", true)
  local ctx = (RC and RC.GroupContext) and RC.GroupContext() or "solo"
  if not CameraFlip.Allowed(p, ctx) then camSay(self, "request ignored: off or gated out (" .. tostring(ctx) .. ")"); return end
  if self._cameraFlipped then return end
  if now then
    self:CamDoFlip(true)
  else
    camSay(self, "armed for the next melee hit")
    self._cameraArm = GetTime() + CAMERA_ARM_WINDOW
    self:RegisterEvent("PLAYER_SWING", "OnCameraSwing")
  end
end

_G.NockCamFlip = function(now) CameraFlip:CamFlipRequest(now) end
_G.NockCamFace = function() CameraFlip:CamFace() end

function CameraFlip:OnCameraSwing(event, duration, kind)
  local T = _G.Enum and _G.Enum.PlayerSwingType
  if not (T and kind == T.MainHand) or not self._cameraArm then return end
  local due = GetTime() <= self._cameraArm
  self._cameraArm = nil
  camSay(self, due and "melee hit: armed turn fires" or "melee hit: arm expired")
  if due then self:CamDoFlip(true) end
end

function CameraFlip:CameraData()
  local d = { apis = {}, cvars = {}, restrictions = (Nock.ForeverProbe and Nock.ForeverProbe.RestrictionRows) and Nock.ForeverProbe.RestrictionRows() or {}, trials = self._cameraTrials or {},
    blocked = self._blocked or {}, flipped = self._cameraFlipped, armed = self._cameraArm ~= nil,
    delay = self._cameraDelay, delayBack = self._cameraDelayBack }
  for _, name in ipairs(CAMERA_APIS) do d.apis[#d.apis + 1] = { name, _G[name] ~= nil } end
  for _, name in ipairs(CAMERA_CVARS) do d.cvars[#d.cvars + 1] = { name, cameraGetCVar(name) or "?" } end
  d.facing = cameraFacing()
  d.moving = _G.IsPlayerMoving and Nock.Flavor.Plain(_G.IsPlayerMoving())
  d.mouselooking = cameraMouselooking()
  d.combat = Nock.Flavor.Plain(_G.InCombatLockdown and _G.InCombatLockdown())
  return d
end

-- Setup assistant (`camera setup`, toggles). Step 1: RMB release with the
-- camera behind the character = the baseline facing, and the normal view is
-- saved as view 2. Step 2: LMB held, Turn key tapped until baseline + 180;
-- the LMB release there saves view 1. Turn-key taps also fire the turning
-- events, so a stop while LMB is held never resets the baseline.

-- Pure: how far the current facing is from baseline + 180 (signed degrees)
-- and whether that is inside the tolerance.
function CameraFlip.CameraSetupCheck(baseline, facing, tol)
  local d = CameraFlip.FacingDelta(baseline, facing)
  if not d then return nil, false end
  local off = d - 180
  if off <= -180 then off = off + 360 end
  return off, math.abs(off) <= (tol or CAMERA_SETUP_TOL)
end

local CAMERA_MACRO_HELP = [[Weave camera flip macros.

Raptor Strike (the last line turns you away on the next melee hit):
#showtooltip
/stopcasting
/cast Raptor Strike
/startattack
/run NockCamFlip()

Auto Shot spam (the last line turns you back; safe to spam):
#showtooltip
/cast !Auto Shot
/run NockCamFace()

Prefer turning on the key press itself instead of the hit? Use /run NockCamFlip(true) in the Raptor macro.
Camera Following Style must stay "Never adjust camera" (Nock > Utilities > Camera & world).
Changed your zoom or tilt? /nock probe camera setup again.]]

-- Settings button and `/nock camera macros`: the two macros in a copybox.
function CameraFlip:ShowMacros()
  if Nock.UI and Nock.UI.ShowCopyBox then Nock.UI.ShowCopyBox(CAMERA_MACRO_HELP) else Nock:Print(CAMERA_MACRO_HELP) end
end

local function cameraStyleWrong()
  return tostring(cameraGetCVar("cameraSmoothStyle") or "?") ~= "0"
end

-- The window is Forever/CameraSetupView.lua; this is its controller.
-- `step`: open at (or jump to) that step, for looking at the pages.
function CameraFlip:CameraSetup(step)
  local S = self._cameraSetup
  local V = Nock.CameraSetupView
  if S and S.active and step then S.step = step; return end
  if S and S.active then
    S.active = false
    if V then V:Close() end
    self:UnregisterEvent("PLAYER_STARTED_TURNING")
    self:UnregisterEvent("PLAYER_STOPPED_TURNING")
    self:UnregisterEvent("PLAYER_STOPPED_LOOKING")
    Nock:Print("camera setup closed")
    return
  end
  if not V then Nock:Print("camera setup: the window is not loaded"); return end
  if not S then S = {}; self._cameraSetup = S end
  S.active, S.step, S.baseline, S.rmb, S.savedOff, S.savedZoom = true, step or 1, nil, false, nil, nil
  -- The aura sets the instant view blend at init; the snap needs it.
  cameraSetCVar("cameraViewBlendStyle", "2")
  local probe = self
  V:Open({
    onClose = function() probe:CameraSetup() end,
    onSkip = function() probe:CameraSetup() end,
    onBack = function() S.step, S.baseline = 1, nil end,
    onRedo = function() S.step, S.baseline, S.savedOff = 1, nil, nil end,
    onFix = function() cameraSetCVar("cameraSmoothStyle", "0"); Nock:Print("camera setup: Camera Following Style set to Never adjust") end,
    onTestOut = function() probe:CamDoFlip(false) end,
    onTestBack = function() probe:CamFace() end,
    onCopy = function(code)
      local text = code .. "\n\n----\n" .. CAMERA_MACRO_HELP
      if Nock.UI and Nock.UI.ShowCopyBox then Nock.UI.ShowCopyBox(text) else Nock:Print(text) end
    end,
  })
  self:RegisterEvent("PLAYER_STARTED_TURNING", "OnCameraSetupEvent")
  self:RegisterEvent("PLAYER_STOPPED_TURNING", "OnCameraSetupEvent")
  self:RegisterEvent("PLAYER_STOPPED_LOOKING", "OnCameraSetupEvent")
end

function CameraFlip:OnCameraSetupEvent(event)
  local S = self._cameraSetup
  if not (S and S.active) then return end
  if event == "PLAYER_STARTED_TURNING" then
    S.rmb = cameraButtonDown("RightButton")
  elseif event == "PLAYER_STOPPED_TURNING" then
    -- Only an RMB release with LMB up sets the baseline (a tap of a Turn key
    -- while LMB is held is step 2's own adjustment).
    if S.rmb and not cameraButtonDown("LeftButton") and S.step ~= 3 then
      S.baseline = cameraFacing()
      if S.baseline then
        S.step = 2
        local errs = {}
        cameraCall(errs, "SaveView", 2)
        if #errs > 0 then Nock:Print("camera setup: " .. errs[1]) end
      end
    end
    S.rmb = false
  elseif event == "PLAYER_STOPPED_LOOKING" and S.step == 2 then
    local off, ok = CameraFlip.CameraSetupCheck(S.baseline, cameraFacing())
    if ok then
      local errs = {}
      cameraCall(errs, "SaveView", 1)
      if #errs == 0 then
        S.step, S.savedOff, S.savedZoom = 3, off, cameraZoom()
        Nock:Print(("camera setup: view saved at %+.1f deg from 180, zoom %s"):format(off, tostring(S.savedZoom)))
      else
        Nock:Print("camera setup: " .. errs[1])
      end
    end
  end
end

-- Central tick: feed the window (it rebuilds only when a value moves).
function CameraFlip:Refresh()
  local S = self._cameraSetup
  local V = Nock.CameraSetupView
  if not (S and S.active and V) then return end
  if not V:IsOpen() then self:CameraSetup(); return end
  local f = cameraFacing()
  local deg = f and math.floor(f * 1800 / math.pi + 0.5) / 10 or nil
  local off, ok
  if S.step == 2 and f then off, ok = CameraFlip.CameraSetupCheck(S.baseline, f) end
  local z = cameraZoom()
  V:Render({ step = S.step, facingDeg = deg, off = off and math.floor(off * 10 + 0.5) / 10 or nil, ok = ok,
    zoom = type(z) == "number" and math.floor(z * 10 + 0.5) / 10 or nil,
    styleWarn = cameraStyleWrong(), savedOff = S.savedOff, savedZoom = S.savedZoom })
end

function CameraFlip:Command(rest)
  local sub, arg = (rest or ""):match("^(%w*)%s*([%w%.]*)")
  if sub == "setup" then self:CameraSetup(tonumber(arg))
  elseif sub == "macros" then self:ShowMacros()
  elseif sub == "show" then
    local errs = {}
    cameraCall(errs, "SetView", 1)
    Nock:Print(#errs > 0 and ("camera show: " .. errs[1]) or "camera: view 1 shown (the camera should look at your face)")
  elseif sub == "out" then self:CamDoFlip(false)
  elseif sub == "back" then self:CamFace()
  elseif sub == "delay" then
    -- `delay <out> [<back>]`: seconds, 0 = next frame. One value sets the
    -- out-turn only.
    local out, backArg = (rest or ""):match("^delay%s+(%S+)%s*(%S*)")
    local function parse(v) return tonumber(v) end
    self._cameraDelay = parse(out)
    if backArg and backArg ~= "" then self._cameraDelayBack = parse(backArg) end
    Nock:Print(("camera delay out %s  back %s"):format(tostring(self._cameraDelay or CAMERA_DELAY_DEFAULT),
      tostring(self._cameraDelayBack or CAMERA_DELAY_BACK_DEFAULT)))
  elseif sub == "debug" then
    self._cameraDebug = (arg ~= "off")
    Nock:Print("camera debug " .. (self._cameraDebug and "on" or "off"))
  elseif sub == "reset" then
    self._cameraFlipped, self._cameraArm = false, nil
    Nock:Print("camera latch reset")
  else
    local text = CameraFlip.CameraReport(self:CameraData())
    if Nock.UI and Nock.UI.ShowCopyBox then Nock.UI.ShowCopyBox(text) else Nock:Print(text) end
  end
end

