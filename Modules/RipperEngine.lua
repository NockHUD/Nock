-- Modules/RipperEngine.lua
-- Pure countdown engine for the Dimensional Ripper - Area 52 (item 30542) and
-- Ultrasafe Transporter: Toshley's Station (item 30544) trick (no WoW APIs --
-- testable under standalone LuaJIT via Tests/ripper_engine_test.lua).
-- Modules/RipperWatch.lua owns the cast events; UI/Frame_RipperCountdown.lua
-- paints the big text.
--
-- The trick (user, 2026-08-27): both trinkets are a long cast that teleports
-- you and rolls a side effect -- some of them beneficial (a bigger character is
-- a real help in a raid). Closing the client (ALT F4) about a second BEFORE the
-- cast ends leaves you where you are but STILL hands out the side effect. So:
-- the deadline is the cast's end minus a lead, the numerals count the whole
-- seconds down to it (9 .. 1), and from the deadline on it reads ALT F4.
-- A first cut flipped a second EARLY (ALT F4 for the second before the
-- deadline) and the user's first real try failed on it (2026-08-27).

local Engine = {}

Engine.DEFAULT = {
  lead = 1.0,   -- seconds before the cast's end at which to close the client
}

Engine.LABEL = {
  go = "ALT F4",
}

function Engine.New()
  return {
    startTime = nil,   -- the cast's span, GetTime() seconds
    endTime   = nil,
    deadline  = nil,   -- endTime - lead, floored at startTime
    lead      = Engine.DEFAULT.lead,
    goSeen    = false, -- the flip to ALT F4 has been handed out
    _go       = false, -- the flip, waiting for TakeGo
  }
end

function Engine.Active(st)
  return st.deadline ~= nil
end

local function place(st, startTime, endTime, lead)
  st.startTime = startTime
  st.endTime   = endTime
  local dl = endTime - lead
  if dl < startTime then dl = startTime end
  st.deadline = dl
end

-- A watched cast has started. `lead` is the profile's; nil takes the default.
function Engine.Begin(st, startTime, endTime, lead)
  st.lead = lead or Engine.DEFAULT.lead
  place(st, startTime, endTime, st.lead)
  st.goSeen, st._go = false, false
end

-- The cast was pushed back (UNIT_SPELLCAST_DELAYED): same lead, new span.
function Engine.Retime(st, startTime, endTime)
  if not st.deadline then return end
  place(st, startTime, endTime, st.lead)
end

function Engine.End(st)
  st.startTime, st.endTime, st.deadline = nil, nil, nil
  st.goSeen, st._go = false, false
end

-- Hands out the flip to ALT F4 exactly once per cast: the sound cue's
-- trigger. Describe must have run at or past the deadline for it to be seen.
function Engine.TakeGo(st)
  if st._go then st._go = false; return true end
  return false
end

-- out = { label, go, remaining, frac }. label is nil when idle.
--   label      the numeral (whole seconds to the deadline, rounded up: 9 .. 1)
--              while the deadline is ahead; ALT F4 from the deadline on, until
--              the cast is gone.
--   go         true while the label is ALT F4
--   remaining  seconds to the deadline, floored at 0
--   frac       progress through the cast, 0..1
function Engine.Describe(st, now, out)
  out = out or {}
  if not st.deadline then
    out.label, out.go, out.remaining, out.frac = nil, false, 0, 0
    return out
  end
  local rem = st.deadline - now
  if rem < 0 then rem = 0 end
  out.remaining = rem
  local span = st.endTime - st.startTime
  local frac = span > 0 and (now - st.startTime) / span or 1
  if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
  out.frac = frac
  if rem <= 0 then
    out.label, out.go = Engine.LABEL.go, true
    if not st.goSeen then st.goSeen = true; st._go = true end
  else
    out.label, out.go = tostring(math.ceil(rem - 1e-9)), false
  end
  return out
end

-- Bound onto the addon table when it exists (in-game) -- under the test
-- harness it is absent and the return value is what the test binds. Same
-- shape as Modules/SlammerEngine.lua.
local Nock = rawget(_G, "Nock")
if Nock then Nock.RipperEngine = Engine end
return Engine
