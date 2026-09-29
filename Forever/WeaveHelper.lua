-- Forever/WeaveHelper.lua
-- The Forever weave helper: feeds Forever/WeaveEngine.lua with the swing events, movement and the tick, publishes state.weave.

-- Every input is plain in combat on Forever: PLAYER_SWING (both kinds),
-- PLAYER_STARTED/STOPPED_MOVING, the ladder's zone and rest band, the swing
-- timers, the character's facing and the bound movement keys (IsKeyDown,
-- probe 2026-09-29: the glide's only velocity source, since speed is
-- secret). Distance is never read. The learned legs and the shoot-edge
-- fraction live in db.char.weaveLegs (v = 2).

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local WeaveHelper = Nock:NewModule("WeaveHelper", "AceEvent-3.0")
local E = Nock.WeaveEngine

-- Bound keys per movement group (GetBindingKey, rebuilt on UPDATE_BINDINGS).
local ACTIONS = {
  fwd = { "MOVEFORWARD" }, back = { "MOVEBACKWARD" },
  strafeL = { "STRAFELEFT" }, strafeR = { "STRAFERIGHT" },
  turnL = { "TURNLEFT" }, turnR = { "TURNRIGHT" },
  steer = { "MOVEANDSTEER" },
}
local GROUPS = { "fwd", "back", "strafeL", "strafeR", "turnL", "turnR", "steer" }
local LEGS_VERSION = 2
local DIAGONAL = 0.707

-- Pure: the movement keys' intent in the character's frame, two numbers in
-- -1..1: forward (forward keys, move-and-steer or both mouse buttons = 1,
-- backward = -1, both = 0: W+S stands still on Forever, probe 2026-09-29)
-- and sideways (strafe keys, or a turn key under the right button, right =
-- 1). A diagonal scales both by 0.707. Moving with no key down is autorun
-- (forward); a key held while the client says not moving (rooted, stunned,
-- typing in chat) is nothing. The engine projects the pair onto the
-- target bearing.
function WeaveHelper.Radial(k, moving)
  if not moving then return 0, 0 end
  local fwd = k.fwd or k.steer or (k.lmb and k.rmb)
  local back = k.back
  local axis = (fwd and 1 or 0) - (back and 1 or 0)
  local lat = (k.strafeR and 1 or 0) - (k.strafeL and 1 or 0)
  if k.rmb then lat = lat + (k.turnR and 1 or 0) - (k.turnL and 1 or 0) end
  if lat > 1 then lat = 1 elseif lat < -1 then lat = -1 end
  if axis == 0 and lat == 0 then
    if not fwd and not back and not k.strafeL and not k.strafeR and not k.turnL and not k.turnR then return 1, 0 end
    return 0, 0
  end
  if axis ~= 0 and lat ~= 0 then return axis * DIAGONAL, lat * DIAGONAL end
  return axis, lat
end

function WeaveHelper:RebuildKeys()
  local GBK = _G.GetBindingKey
  local K = {}
  for _, group in ipairs(GROUPS) do
    local list = {}
    for _, action in ipairs(ACTIONS[group]) do
      local k1, k2
      if GBK then k1, k2 = GBK(action) end
      -- a chord ("SHIFT-W") reads its base key; the moving gate covers the rest
      if type(k1) == "string" then list[#list + 1] = k1:match("([^%-]+)$") or k1 end
      if type(k2) == "string" then list[#list + 1] = k2:match("([^%-]+)$") or k2 end
    end
    K[group] = list
  end
  self._keys = K
end

-- A key name the client refuses (a wheel, an odd chord) reads as up.
local function keyDown(IKD, key)
  local okc, v = pcall(IKD, key)
  return okc and Nock.Flavor.Plain(v) == true
end

local function anyDown(IKD, list)
  for i = 1, #list do
    if keyDown(IKD, list[i]) then return true end
  end
  return false
end

-- The bound keys and the mouse buttons into the reused table k; false for
-- everything when the client has no IsKeyDown.
function WeaveHelper:ReadKeys(k)
  local IKD = _G.IsKeyDown
  local K = self._keys
  if not K then self:RebuildKeys(); K = self._keys end
  if not IKD then
    for _, group in ipairs(GROUPS) do k[group] = false end
    k.lmb, k.rmb = false, false
    return k
  end
  for _, group in ipairs(GROUPS) do k[group] = anyDown(IKD, K[group]) end
  k.lmb, k.rmb = keyDown(IKD, "LeftButton"), keyDown(IKD, "RightButton")
  return k
end

local function swingType(name)
  local T = _G.Enum and _G.Enum.PlayerSwingType
  return T and T[name]
end

-- Pure: the profile switch (unset = on; Forever's default is on).
function WeaveHelper.Enabled(p)
  return not (p and p.weaveHelperEnabled == false)
end

-- The character's facing, radians; nil when the client will not say (then
-- no leg ever reverses).
local function facing()
  local f = _G.GetPlayerFacing and Nock.Flavor.Plain(_G.GetPlayerFacing())
  return type(f) == "number" and f or nil
end

local function seed()
  local p = Nock.db and Nock.db.profile
  return p and tonumber(p.weaveLegSeed) or nil
end

-- The start window slider (weaveStartWindow): seconds after a shot in which
-- GO is offered, directly or at the end of a WAIT.
function WeaveHelper:ApplyWindow()
  local p = Nock.db and Nock.db.profile
  if self.st then E.SetWindow(self.st, p and p.weaveStartWindow) end
end

function WeaveHelper:OnEnable()
  local legs = Nock.db and Nock.db.char and Nock.db.char.weaveLegs
  if legs and legs.v ~= LEGS_VERSION then legs = nil end   -- pre-v2 legs were shoot-edge legs
  self.st = E.New(legs and legs.legIn, legs and legs.legOut, seed(), legs and legs.shootFrac, legs and legs.legOutBack)
  self:ApplyWindow()
  self._moving = (_G.IsPlayerMoving and _G.IsPlayerMoving() == true) or false
  self._samples = {}
  self._k = {}
  self:RebuildKeys()
  self:RegisterEvent("UPDATE_BINDINGS", "RebuildKeys")
  self:RegisterEvent("PLAYER_SWING")
  self:RegisterEvent("PLAYER_TARGET_CHANGED")
  self:RegisterEvent("PLAYER_REGEN_ENABLED")
  self:RegisterEvent("PLAYER_STARTED_MOVING")
  self:RegisterEvent("PLAYER_STOPPED_MOVING")
  -- Spec §6 probe 3: does the client's melee-edge signal fire here? Counted,
  -- never used (the finder header says it never did).
  self.mhRangeEvents = 0
  local ST, kind = _G.C_SwingTimer, swingType("MainHand")
  if ST and ST.EnableRangeCheck and kind ~= nil then
    ST.EnableRangeCheck(kind, true)
    self:RegisterEvent("PLAYER_SWING_RANGE_UPDATE")
  end
end

function WeaveHelper:PLAYER_SWING_RANGE_UPDATE(event, kind)
  if kind == swingType("MainHand") then self.mhRangeEvents = (self.mhRangeEvents or 0) + 1 end
end

-- The edges reach the engine at their own time: a stop between two ticks
-- must not count as moving until the next Refresh.
function WeaveHelper:PLAYER_STARTED_MOVING()
  self._moving = true
  E.SetMoving(self.st, true, GetTime())
end
function WeaveHelper:PLAYER_STOPPED_MOVING()
  self._moving = false
  E.SetMoving(self.st, false, GetTime())
end

local SAMPLE_MAX = 24

function WeaveHelper:PLAYER_SWING(event, duration, kind)
  local now = GetTime()
  local S = self._samples
  if kind == swingType("Ranged") then
    local shot = E.RangedSwing(self.st, now, facing())
    S[#S + 1] = { t = now, kind = "Ranged", shot = shot, stage = self.st.stage }
  elseif kind == swingType("MainHand") then
    local before = self.st.stage
    E.MeleeHit(self.st, now, facing())
    S[#S + 1] = { t = now, kind = "MainHand", stage = self.st.stage, legIn = self.st.legIn }
    -- the hit's own stage change (STRIKE -> OUT) happens here, between ticks
    if self.st.stage ~= before then
      self:LogTransition(now, before, self.st.stage, self.st.zone, 0, 0, 0, self.st.radial, self.st.face, self.st.lateral)
      self:SendMessage("NOCK_WEAVE_STAGE", self.st.stage, before)
    end
  else
    return
  end
  if #S > SAMPLE_MAX then table.remove(S, 1) end
end

function WeaveHelper:PLAYER_TARGET_CHANGED()
  E.TargetChanged(self.st, GetTime())
end

function WeaveHelper:PLAYER_REGEN_ENABLED()
  E.TargetChanged(self.st, GetTime())
end

function WeaveHelper:SaveLegs()
  local c = Nock.db and Nock.db.char
  if not c then return end
  c.weaveLegs = c.weaveLegs or {}
  c.weaveLegs.v, c.weaveLegs.legIn, c.weaveLegs.legOut, c.weaveLegs.shootFrac =
    LEGS_VERSION, self.st.legIn, self.st.legOut, self.st.shootFrac
  c.weaveLegs.legOutBack = self.st.learnedOutBack and self.st.legOutBack or nil
end

-- The seed slider: every leg not learned yet follows it at once; a learned
-- leg keeps its measurement (Config/Options.lua weaveLegSeed set).
function WeaveHelper:ApplySeed()
  local st = self.st
  if not st then return end
  local s = E.New(nil, nil, seed())
  if not st.learnedIn then st.legIn = s.legIn end
  if not st.learnedOut then st.legOut = s.legOut end
  if not st.learnedOutBack then st.legOutBack = st.legOut end
end

-- Settings button: forget the learned legs, back to the seed.
function WeaveHelper:ResetLegs()
  local c = Nock.db and Nock.db.char
  if c then c.weaveLegs = nil end
  self.st = E.New(nil, nil, seed())
  self:ApplyWindow()
end

-- Every stage change with the inputs the decision saw: a GO nobody can
-- reproduce needs its evidence (/nock probe weave). Entries are pooled and
-- reused in a ring (no allocation once it is full).
local TRANSITION_MAX = 40
function WeaveHelper:LogTransition(now, from, to, zone, age, melee, raptor, radial, face, lateral)
  local T = self._transitions
  if not T then T = { n = 0, head = 0 }; self._transitions = T end
  T.head = T.head % TRANSITION_MAX + 1
  if T.n < TRANSITION_MAX then T.n = T.n + 1 end
  local e = T[T.head]
  if not e then e = {}; T[T.head] = e end
  e.t, e.from, e.to, e.zone, e.age, e.melee, e.raptor, e.moving = now, from, to, zone, age, melee, raptor, self._moving == true
  e.radial, e.face, e.lateral = radial, face, lateral
end

-- Oldest first.
function WeaveHelper:Transitions()
  local T, out = self._transitions, {}
  if not T then return out end
  for i = 1, T.n do
    local ix = (T.head - T.n + i - 1) % TRANSITION_MAX + 1
    out[#out + 1] = T[ix]
  end
  return out
end

-- The last swing events with the stage they landed in (/nock probe weave).
function WeaveHelper:Samples()
  local out = {}
  for i = 1, #self._samples do out[i] = self._samples[i] end
  return out
end

-- Every frame: the engine needs the leg clock at frame rate for the glide.
function WeaveHelper:Refresh(state)
  local st, w = self.st, state.weave
  local now = GetTime()
  if not WeaveHelper.Enabled(Nock.db and Nock.db.profile) then
    if w.stage ~= nil or w.legKind ~= nil then
      E.TargetChanged(st, now)
      E.Publish(st, w)
    end
    -- A hit that landed while off must never re-anchor the swing later.
    st.hitAt, st.rangedSeen, st.reanchored = nil, true, true
    return
  end
  local t = state.target
  local zone = (t and t.exists == true and t.alive == true and t.friendly ~= true) and t.rangeState or nil
  local m, r = state.melee, state.ranged
  local meleeReadyIn = (m.swingStart > 0) and (m.swingRemaining or 0) or 0
  -- Raptor's cooldown from the ledger (plain: own casts + learned lengths);
  -- unknown reads as ready, the tile's grey says the rest.
  local cd = state.cooldowns and state.cooldowns.Raptor
  local raptorReadyIn = (cd and cd.ready == false and type(cd.remaining) == "number") and cd.remaining or 0
  local rangedElapsed = (r.swingStart > 0) and (now - r.swingStart) or 0
  local rest = t and t.ladderRest
  local k = self:ReadKeys(self._k)
  local radial, lateral = WeaveHelper.Radial(k, self._moving)
  local before = st.stage
  E.Step(st, now, zone, rest, radial, facing(), meleeReadyIn, r.swingRemaining, r.queueWindow, raptorReadyIn, rangedElapsed, lateral)
  if st.stage ~= before then
    self:LogTransition(now, before, st.stage, zone, rangedElapsed, meleeReadyIn, raptorReadyIn, st.radial, st.face, st.lateral)
    -- The cue sounds (Forever/RangeCues.lua) and anything else that wants a
    -- stage edge listen here; no module calls another's internals.
    self:SendMessage("NOCK_WEAVE_STAGE", st.stage, before)
  end
  -- Forever: a melee hit resets the ranged swing. When the client sends no
  -- Ranged event of its own, the swing is re-anchored on the hit here.
  local hitAt = E.ReanchorDue(st, now)
  if hitAt and r.swingDuration > 0 then r.swingStart = hitAt end
  if st.learnedAt then
    self:SaveLegs()
    st.learnedAt = nil
  end
  E.Publish(st, w)
end
