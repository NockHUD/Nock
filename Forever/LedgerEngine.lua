-- Forever/LedgerEngine.lua
-- Pure cast ledger: own cast stamps + learned cooldowns -> plain remaining and
-- ready per spell, with shared-cooldown groups. No WoW API; LuaJIT-tested.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")

local Engine = {}
Nock.LedgerEngine = Engine

function Engine.New()
  return {
    learned = {},   -- [spellID] = cooldown seconds
    start   = {},   -- [groupKey] = GetTime() of the last start (stamp or seed)
    dur     = {},   -- [groupKey] = duration used for that start
    group   = {},   -- [spellID] = groupKey (the first member's id for linked spells)
  }
end

local function groupOf(s, spellID)
  return s.group[spellID] or spellID
end

function Engine.Learn(s, spellID, cooldown)
  if type(cooldown) ~= "number" or cooldown <= 0 then return end
  s.learned[spellID] = cooldown
end

function Engine.Known(s, spellID)
  return s.learned[spellID] ~= nil
end

-- Spells sharing one cooldown: all members map to the first member's key.
function Engine.Link(s, spellIDs)
  local key = spellIDs[1]
  for i = 1, #spellIDs do s.group[spellIDs[i]] = key end
end

local function setIfLater(s, key, start, duration)
  local endsAt = start + duration
  local cur = s.start[key]
  if cur and (cur + (s.dur[key] or 0)) >= endsAt then return end
  s.start[key], s.dur[key] = start, duration
end

function Engine.OnCast(s, spellID, now)
  local cd = s.learned[spellID]
  if not cd then return end
  setIfLater(s, groupOf(s, spellID), now, cd)
end

-- A plain API reading (snapshot at combat start). Zero readings are ignored:
-- "not on cooldown" is what the API says for a spell it has no data for too.
function Engine.Seed(s, spellID, start, duration)
  if type(start) ~= "number" or type(duration) ~= "number" then return end
  if start <= 0 or duration <= 0 then return end
  setIfLater(s, groupOf(s, spellID), start, duration)
end

-- Out-of-combat truth replaces the entry; start == 0 clears the running entry
-- (the learned duration stays).
function Engine.Reconcile(s, spellID, start, duration)
  local key = groupOf(s, spellID)
  if type(start) == "number" and start > 0 and type(duration) == "number" and duration > 0 then
    s.start[key], s.dur[key] = start, duration
  else
    s.start[key], s.dur[key] = nil, nil
  end
end

function Engine.Cooldown(s, spellID, now)
  local key = groupOf(s, spellID)
  local start, dur = s.start[key], s.dur[key]
  if not start or not dur or dur <= 0 then return 0, 0, 0, true end
  local remaining = start + dur - now
  if remaining <= 0 then return start, dur, 0, true end
  return start, dur, remaining, false
end

return Engine
