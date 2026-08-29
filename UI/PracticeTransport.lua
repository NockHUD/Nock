-- UI/PracticeTransport.lua
-- The replay transport, shared by the stage and the expert combat log: skip / prev clip / play-pause / next clip / skip, the readout, the track with its clip markers and handle, and close.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local Skin = Nock.Skin
Nock.UI = Nock.UI or {}

local TR_BTN, TR_ICON_GAP = 22, 2
local TR_TRACK_H, TR_LINE, TR_HANDLE_W, TR_HANDLE_H, TR_MARK_W = 16, 3, 6, 12, 2
local TR_TIME_W = 96

local Transport = {}
Transport.__index = Transport
Nock.UI.PracticeTransport = Transport

local function practice() return Nock:GetModule("Practice", true) end

-- One icon button. `act` runs on the click; the icon dims at rest.
local function trButton(tr, icon, tip, act)
  local b = CreateFrame("Button", nil, tr.frame)
  b:SetSize(TR_BTN, TR_BTN)
  local ico = b:CreateTexture(nil, "ARTWORK")
  ico:SetPoint("CENTER", b, "CENTER", 0, 0)
  Skin.Icon(ico, icon, "ink2")
  Skin.IconSize(ico)
  b.ico, b.iconName = ico, icon
  b:SetScript("OnEnter", function() Skin.Icon(ico, b.iconName, "ink") end)
  b:SetScript("OnLeave", function() Skin.Icon(ico, b.iconName, "ink2") end)
  b:SetScript("OnClick", act)
  b.tipTitle = tip
  return b
end

-- Build one on `parent`, `height` tall, anchored by the caller (`tr.frame`).
-- `inset` is the horizontal inset of the outer buttons. The frame starts
-- hidden; Paint shows it while a replay is up and no fight runs.
function Transport.New(parent, height, inset)
  local tr = setmetatable({}, Transport)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(height)
  Skin.Surface(f, "surface")
  local rule = Skin.Rule(f, "lineSoft")
  rule:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  rule:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
  rule:SetHeight(1)
  tr.frame = f
  inset = inset or 8
  local function replayOf() local p = practice(); return p, p and p._replay end
  local start = trButton(tr, "skipstart", "Start of the fight", function()
    local p, rp = replayOf(); if rp then tr._play = false; p:ReplayAt(rp.t0) end
  end)
  start:SetPoint("LEFT", f, "LEFT", inset, 0)
  local prev = trButton(tr, "prev", "Previous delayed auto", function()
    local p, rp = replayOf(); if rp then tr._play = false; p:ReplayStep(-1, "clip") end
  end)
  prev:SetPoint("LEFT", start, "RIGHT", TR_ICON_GAP, 0)
  local play = trButton(tr, "play", "Play / pause", function()
    local p, rp = replayOf()
    if not rp then return end
    -- Play from the end starts over.
    if not tr._play and rp.at >= rp.t1 - 1e-6 then p:ReplayAt(rp.t0) end
    tr._play = not tr._play
    tr._playAt = GetTime()
  end)
  play:SetPoint("LEFT", prev, "RIGHT", TR_ICON_GAP, 0)
  local nxt = trButton(tr, "next", "Next delayed auto", function()
    local p, rp = replayOf(); if rp then tr._play = false; p:ReplayStep(1, "clip") end
  end)
  nxt:SetPoint("LEFT", play, "RIGHT", TR_ICON_GAP, 0)
  local fin = trButton(tr, "skipend", "End of the fight", function()
    local p, rp = replayOf(); if rp then tr._play = false; p:ReplayAt(rp.t1) end
  end)
  fin:SetPoint("LEFT", nxt, "RIGHT", TR_ICON_GAP, 0)
  local time = f:CreateFontString(nil, "OVERLAY")
  Skin.Font(time, "monoMedium", Skin.SIZES.mono)
  time:SetPoint("LEFT", fin, "RIGHT", 10, 0)
  time:SetWidth(TR_TIME_W)
  time:SetJustifyH("LEFT"); time:SetWordWrap(false)
  Skin.Text(time, "ink")
  local close = trButton(tr, "close", "Leave the replay", function()
    local p = practice(); if p and p.ReplayOff then tr._play = false; p:ReplayOff() end
  end)
  close:SetPoint("RIGHT", f, "RIGHT", -inset, 0)
  -- The track: a mouse strip; the line, the played part, the markers and
  -- the handle are textures on it. A press anywhere on it scrubs to the
  -- cursor and keeps following it until the button goes up (Scrub, stepped
  -- from the owner's tick).
  local track = CreateFrame("Frame", nil, f)
  track:SetPoint("LEFT", time, "RIGHT", 6, 0)
  track:SetPoint("RIGHT", close, "LEFT", -10, 0)
  track:SetHeight(TR_TRACK_H)
  track:EnableMouse(true)
  local line = track:CreateTexture(nil, "BACKGROUND")
  line:SetPoint("LEFT", track, "LEFT", 0, 0)
  line:SetPoint("RIGHT", track, "RIGHT", 0, 0)
  line:SetHeight(TR_LINE)
  Skin.Paint(line, "line", 1)
  local played = track:CreateTexture(nil, "BORDER")
  played:SetPoint("LEFT", track, "LEFT", 0, 0)
  played:SetHeight(TR_LINE)
  played:SetWidth(1)
  Skin.Paint(played, "accent", 0.8)
  local handle = track:CreateTexture(nil, "OVERLAY")
  handle:SetSize(TR_HANDLE_W, TR_HANDLE_H)
  handle:SetPoint("CENTER", track, "LEFT", 0, 0)
  Skin.Paint(handle, "ink", 1)
  track:SetScript("OnMouseDown", function() tr._play = false; tr._scrubOn = true; tr:Scrub() end)
  track:SetScript("OnMouseUp", function() tr._scrubOn = false end)
  tr.start, tr.prev, tr.play, tr.next, tr["end"], tr.close = start, prev, play, nxt, fin, close
  tr.time, tr.track, tr.line, tr.played, tr.handle = time, track, line, played, handle
  tr.marks, tr.nMarks = {}, 0
  f:Hide()
  return tr
end

-- The frame's own Show/Hide/IsShown, for owners and tests that treat the
-- transport as a frame.
function Transport:IsShown() return self.frame:IsShown() end
function Transport:Show() self.frame:Show() end
function Transport:Hide() self.frame:Hide() end
function Transport:SetPoint(...) self.frame:SetPoint(...) end
function Transport:ClearAllPoints() self.frame:ClearAllPoints() end
function Transport:SetFrameLevel(l) self.frame:SetFrameLevel(l) end
function Transport:GetFrameLevel() return self.frame:GetFrameLevel() end
function Transport:GetHeight() return self.frame:GetHeight() end
function Transport:IsPlaying() return self._play and true or false end

-- The track's cursor position as a replay time, applied. From the mouse-down
-- and then from every tick while the button is held.
function Transport:Scrub()
  local p = practice()
  local rp = p and p._replay
  if not rp then self._scrubOn = false; return end
  if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then self._scrubOn = false; return end
  local track = self.track
  local left, w = track:GetLeft(), track:GetWidth()
  if not (left and w and w > 0) then return end
  local x = GetCursorPosition()
  local es = track:GetEffectiveScale()
  if es and es > 0 then x = x / es end
  local frac = (x - left) / w
  if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
  p:ReplayAt(rp.t0 + (rp.t1 - rp.t0) * frac)
end

-- Play: the replay clock runs at 1x from the owner's tick and stops at the
-- end of the fight.
function Transport:Play(p, now)
  local rp = p._replay
  local last = self._playAt or now
  self._playAt = now
  local t = rp.at + (now - last)
  if t >= rp.t1 then
    p:ReplayAt(rp.t1)
    self._play = false
  else
    p:ReplayAt(t)
  end
end

-- Once per tick, BEFORE the owner reads the replay clock: a drag on the
-- track, or play running at 1x. Drops both when the replay is gone.
function Transport:Tick(p, now)
  if p and p._replay then
    if self._scrubOn then self:Scrub() end
    if self._play then self:Play(p, now) end
  elseif self._play or self._scrubOn then
    self._play, self._scrubOn = false, false
  end
end

-- The clip markers: every auto the stream delayed, red for a faulted clip
-- and amber for the paper's own, once per replay (keyed on the stream's
-- length and the fight's origin).
function Transport:PaintMarks(p, rp, w)
  local e = p.engine
  local key = (e and e.n or 0) + (rp.t0 or 0) + w * 1e-3
  if key == self._marksKey then return end
  self._marksKey = key
  local n = 0
  local span = rp.t1 - rp.t0
  if e and span > 0 then
    for i = 1, e.n do
      local ev = e.events[i]
      if ev.kind == "auto" and (ev.delay or 0) > 0.03 then
        n = n + 1
        local t = self.marks[n]
        if not t then
          t = self.track:CreateTexture(nil, "ARTWORK")
          self.marks[n] = t
        end
        t:ClearAllPoints()
        t:SetSize(TR_MARK_W, TR_LINE + 4)
        t:SetPoint("CENTER", self.track, "LEFT", (ev.t - rp.t0) / span * w, 0)
        Skin.Paint(t, ev.clip == "fault" and "bad" or "wait", 1)
        t:Show()
      end
    end
  end
  for i = n + 1, #self.marks do self.marks[i]:Hide() end
  self.nMarks = n
end

-- Once per tick. Shows itself while a replay is up and no fight runs;
-- returns whether it is shown (the owner sizes itself around it).
function Transport:Paint(p, now)
  local rp = p and p._replay
  local on = rp ~= nil and not Nock.state.sim.fightOn
  if on ~= self._on then
    self._on = on
    if on then self.frame:Show() else self.frame:Hide(); self._marksKey = nil end
  end
  if not on then return false end
  local span = rp.t1 - rp.t0
  local at = rp.at - rp.t0
  local w = self.track:GetWidth() or 0
  if w < 1 then w = 1 end
  -- Tenths on the readout; the handle and the played part move every tick.
  local tenths = math.floor(at * 10 + 0.5)
  if tenths ~= self._tenths then
    self._tenths = tenths
    local spanT = math.floor(span * 10 + 0.5)
    self.time:SetText(("%d.%ds / %d.%ds"):format(math.floor(tenths / 10), tenths % 10,
      math.floor(spanT / 10), spanT % 10))
  end
  local x = (span > 0) and (at / span * w) or 0
  self.handle:SetPoint("CENTER", self.track, "LEFT", x, 0)
  self.played:SetWidth(x > 1 and x or 1)
  local playing = self._play and true or false
  if playing ~= self._playing then
    self._playing = playing
    self.play.iconName = playing and "pause" or "play"
    Skin.Icon(self.play.ico, self.play.iconName, "ink2")
  end
  self:PaintMarks(p, rp, w)
  return true
end
