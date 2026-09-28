-- Tests/forever_cooldown_known_test.lua
-- Forever/Cooldowns.lua: the known map covers every entry (not only racials),
-- the spellbook id wins over the catalog's vanilla one, recently-cast tracking
-- for untracked spellbook spells with a cooldown, and the OnEnable migration
-- hook. Run from the repo root: luajit Tests/forever_cooldown_known_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. name) end
end

local now = 100
_G.GetTime = function() return now end
_G.GetRangedHaste = function() return 0 end
_G.Enum = { PlayerSwingType = { MainHand = 0, OffHand = 1, Ranged = 2 } }
local secretCds = false
_G.C_Secrets = { ShouldCooldownsBeSecret = function() return secretCds end, ShouldAurasBeSecret = function() return false end }

-- Frames for the client-cooldown watch: a Cooldown widget records what it was
-- fed and keeps its OnCooldownDone script so a test can end it.
local frames = {}
_G.CreateFrame = function(kind)
  local f = { kind = kind, scripts = {} }
  function f:SetSize() end
  function f:SetPoint() end
  function f:SetAllPoints() end
  function f:SetAlpha() end
  function f:SetHideCountdownNumbers() end
  function f:SetScript(n, fn) self.scripts[n] = fn end
  function f:SetCooldownFromDurationObject(obj) self.fed = obj; self.feeds = (self.feeds or 0) + 1 end
  frames[#frames + 1] = f
  return f
end
local durObjZero = false
local function durObj() return { IsZero = function() return durObjZero end } end

local apiCd = {}   -- [id] = { start, duration }
local apiReads = 0
local sentMsgs = {}
local Nock = {
  Flavor = { forever = true, Plain = function(v) if v == "SECRET" then return nil end return v end },
  API = {
    SpellCooldown = function(id) apiReads = apiReads + 1; if secretCds then return "SECRET", "SECRET", true end; local c = apiCd[id]; if c then return c[1], c[2], true end; return 0, 0, true end,
    SpellCooldownDuration = function() return durObj() end,
    SpellIcon = function(id) return 100000 + id end,
    SpellBaseCooldown = function(id) return _G.GetSpellBaseCooldown and _G.GetSpellBaseCooldown(id) end,
    -- ranks are separate spells on Forever: the name is what they share
    SpellName = function(id) return ({ [3044] = "Arcane Shot", [14281] = "Arcane Shot", [2973] = "Raptor Strike", [14260] = "Raptor Strike", [19574] = "Bestial Wrath", [20554] = "Berserking", [5116] = "Concussive Shot", [999] = "Hunter's Mark", [888] = "Aspect of the Hawk" })[id] or ("spell" .. id) end,
  },
  Constants = { GCD_BASE = 1.5, TRACKED_COOLDOWNS = { { key = "TBC", type = "spell", id = 1, label = "x" } }, REACT_CD_ROWS = { { h = 32, keys = { "TBC" } } }, DIM = { COOLDOWN_ICON = 32, INNER_GAP = 2 }, COOLDOWN_ROWS = 1 },
  db = { profile = {} },
}
local modules = {}
function Nock:NewModule(name) local m = { name = name, events = {}, msgs = {} }
  function m:RegisterEvent(ev, h) self.events[ev] = h or ev end
  function m:RegisterMessage(msg, h) self.msgs[msg] = h or msg end
  function m:SendMessage(msg) sentMsgs[#sentMsgs + 1] = msg end
  modules[name] = m; return m end
function Nock:GetModule(name) return modules[name] end
_G.LibStub = function() return { GetAddon = function() return Nock end } end
dofile("Core/State.lua")
dofile("Forever/LedgerEngine.lua")
dofile("Forever/Snapshot.lua")   -- defines Nock.Restricted
dofile("Forever/Spells.lua")
dofile("Forever/CooldownCatalog.lua")
dofile("Core/CooldownEditor.lua")
dofile("Forever/Spellbook.lua")
dofile("Forever/Cooldowns.lua")

local st = Nock.state

local CD = modules["Cooldowns"]
local book = { ["Arcane Shot"] = 3044, ["Berserking"] = 20554, ["Hunter's Mark"] = 999 }
Nock.ForeverSpellbookNames = function() return book end
_G.GetSpellBaseCooldown = function(id) if id == 999 then return 0 end; return 60000 end
Nock.db.profile.reactCooldownDisabled = { Conc = true }
CD:OnEnable()
CD:UpdateKnown()

-- known map covers every entry, not only racials
ok(CD:IsEntryKnown("Arc") == true, "a trained class spell is known")
ok(CD:IsEntryKnown("BW") == false, "an untaken talent is not known")
ok(CD:IsEntryKnown("Zerk") == true, "own racial known")
ok(CD:IsEntryAvailable("BW") == true, "an unknown CLASS/TALENT entry stays available (greyed, not hidden)")
ok(CD:IsEntryAvailable("Elune") == false, "another race's racial is hidden")
ok(CD:IsEntryAvailable("Fury") == false and CD:IsEntryAvailable("Stone") == false,
   "a name-only racial the spellbook never named is hidden too (tray, flyout, grid)")
do
  local saved = CD._known
  CD._known = nil
  ok(CD:IsEntryAvailable("Zerk") == false, "before the spellbook is read, racials stay hidden")
  ok(CD:IsEntryAvailable("BW") == true, "before the spellbook is read, class/talent entries stay available")
  CD._known = saved
end

-- name resolution: the spellbook id wins over the catalog's vanilla id
book["Bestial Wrath"] = 400574
CD:UpdateKnown()
ok(CD:IsEntryKnown("BW") == true, "learning a talent flips it to known")
local sawVisuals = false
for _, m in ipairs(sentMsgs) do if m == "NOCK_VISUALS_CHANGED" then sawVisuals = true end end
ok(sawVisuals, "a known flip broadcasts NOCK_VISUALS_CHANGED")

-- recently cast (in the spellbook, has a cooldown, not tracked)
local L = {}
Nock.Cooldowns = nil
ok(#CD.RecentPush(L, 5, 3) == 1 and L[1] == 5, "RecentPush inserts")
CD.RecentPush(L, 6, 3); CD.RecentPush(L, 5, 3)
ok(L[1] == 5 and L[2] == 6 and #L == 2, "RecentPush moves a repeat to the front")
CD.RecentPush(L, 7, 3); CD.RecentPush(L, 8, 3)
ok(#L == 3 and L[1] == 8, "RecentPush caps the list")

book["Aspect of the Hawk"] = 888
CD:UNIT_SPELLCAST_SUCCEEDED("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 888)
ok(st.cdRecent[1] == 888, "an untracked spellbook spell with a cooldown is recorded")
CD:UNIT_SPELLCAST_SUCCEEDED("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 999)
ok(st.cdRecent[1] == 888, "a spell with no base cooldown is not recorded")
CD:UNIT_SPELLCAST_SUCCEEDED("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 3044)
ok(st.cdRecent[1] == 888, "a tracked spell is not recorded")
CD:UNIT_SPELLCAST_SUCCEEDED("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 4242)
ok(st.cdRecent[1] == 888, "a spell outside the spellbook is not recorded")

-- a custom spell outside the spellbook is "cannot tell" (nil), not unlearned
Nock.db.profile.cooldownCustom = { { type = "spell", id = 55555, key = "c_spell_55555", label = "Pet Bite" } }
CD:RebuildLists()
CD:UpdateKnown()
ok(CD:IsEntryKnown("c_spell_55555") == nil, "a custom spell outside the spellbook is not known=false")

-- migration ran at enable
ok(next(Nock.db.profile.reactCooldownDisabled) == nil and Nock.db.profile.reactCdMigrated == true, "OnEnable runs the one-time migration")

print(("forever_cooldown_known: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
