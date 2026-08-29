-- Modules/ActionGlowEngine.lua
-- Pure engine for the Kill Command action-bar glow (no WoW APIs — testable
-- under standalone LuaJIT via Tests/action_glow_engine_test.lua).
-- Modules/ActionGlow.lua owns the events, the frame lookups and LibCustomGlow.
--
-- The job: find every bar button that drives an action slot holding Kill
-- Command (directly or through a macro), and turn a proc edge into the
-- minimal set of glow start/stop calls.

local E = {}

E.MAX_SLOT = 120

-- Action slots whose action is one of `spellIds` (a set), scanning 1..MAX_SLOT
-- with `getActionInfo(slot) -> kind, id`. A "macro" action resolves through
-- `macroSpell(macroId) -> spellId` when the caller can provide one.
function E.SlotsFor(getActionInfo, spellIds, macroSpell)
  local out = {}
  for slot = 1, E.MAX_SLOT do
    local kind, id = getActionInfo(slot)
    if kind == "spell" then
      if id and spellIds[id] then out[slot] = true end
    elseif kind == "macro" and macroSpell and id then
      local sid = macroSpell(id)
      if sid and spellIds[sid] then out[slot] = true end
    end
  end
  return out
end

-- The action slot a bar button drives. Blizzard and Dominos keep it on
-- `.action`, LibActionButton (Bartender4, ElvUI) on `_state_action`, and a
-- secure button in its "action" attribute. nil when the frame drives none.
function E.FrameSlot(f)
  if type(f) ~= "table" then return nil end
  local slot = tonumber(f.action) or tonumber(f._state_action)
  if not slot and type(f.GetAttribute) == "function" then
    local okAttr, v = pcall(f.GetAttribute, f, "action")
    if okAttr then slot = tonumber(v) end
  end
  if slot and slot >= 1 then return slot end
  return nil
end

-- The set of frames (keys) among `candidates` whose slot is in `slots`.
function E.ButtonsFor(slots, candidates)
  local out = {}
  for _, f in ipairs(candidates) do
    local slot = E.FrameSlot(f)
    if slot and slots[slot] then out[f] = true end
  end
  return out
end

-- Global frame names to try, per bar family. Absent frames are skipped by
-- the caller; the list is only ever walked on a (rare) rescan.
function E.CandidateNames()
  local names = {}
  local function add(prefix, n) for i = 1, n do names[#names + 1] = prefix .. i end end
  add("ActionButton", 12)
  add("MultiBarBottomLeftButton", 12)
  add("MultiBarBottomRightButton", 12)
  add("MultiBarRightButton", 12)
  add("MultiBarLeftButton", 12)
  add("DominosActionButton", E.MAX_SLOT)
  add("BT4Button", E.MAX_SLOT)
  for bar = 1, 10 do add("ElvUI_Bar" .. bar .. "Button", 12) end
  return names
end

-- The reference WA's Kill Command rule: the proc is "the spell is usable"
-- (IsUsableSpell is true only inside the proc window) and not on cooldown.
-- `petAlive` is the WA's third guard (its pet-health trigger): Kill Command
-- reads usable with no pet out on this client (gate 2026-08-30), so a
-- pet-bound entry passes false here; nil means "no pet requirement".
function E.UsableProc(usable, onCooldown, petAlive)
  if petAlive == false then return false end
  return (usable and not onCooldown) and true or false
end

-- The frames that should glow: the buttons, only while the feature is on and
-- the proc is up. Reuses `buttons` by reference when both hold.
function E.Wanted(enabled, procActive, buttons)
  if enabled and procActive then return buttons end
  return {}
end

-- start = frames in `want` but not in `was`; stop = the reverse.
function E.Diff(was, want)
  local start, stop = {}, {}
  for f in pairs(want) do if not was[f] then start[#start + 1] = f end end
  for f in pairs(was)  do if not want[f] then stop[#stop + 1]  = f end end
  return start, stop
end

if LibStub then
  local AA = LibStub("AceAddon-3.0", true)
  local addon = AA and AA:GetAddon("Nock", true)
  if addon then addon.ActionGlowEngine = E end
end

return E
