-- Forever/Auras.lua
-- The Forever `Auras` module: aspect and Hunter's Mark from own casts while
-- auras are secret, from the aura cache (the truth) while they are not; the
-- eating / drinking records from the cache only.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local Auras = Nock:NewModule("Auras", "AceEvent-3.0")

Auras.refreshInterval = 0.1

local aspectRec = { name = nil, spellId = nil, icon = nil, expirationTime = 0, duration = 0 }
local markRec = { name = nil, spellId = nil, icon = nil, expirationTime = 0, duration = 0,
                  remaining = 0, fromPlayer = true, sourceName = nil }

local function baseSpell(id)
  local CS = _G.C_Spell
  if CS and CS.GetBaseSpell then
    local okc, base = pcall(CS.GetBaseSpell, id)
    if okc and type(base) == "number" and base > 0 then return base end
  end
  return id
end

-- Ranks are separate spells on Forever and GetBaseSpell does not link them
-- (Cooldowns ruling, 2026-09-23), so a rank's cast and aura are matched by
-- NAME to the base id. The map fills lazily: a name the client has not
-- resolved yet is asked for again on the next lookup.
local byName, byNameDone = {}, false
local function nameMap()
  if byNameDone then return byName end
  local S, API = Nock.Spells, Nock.API
  local done = true
  local function add(id)
    local n = Nock.Flavor.Plain(API.SpellName(id))
    if type(n) == "string" then byName[n] = id else done = false end
  end
  for id in pairs(S.ASPECTS) do add(id) end
  add(S.HUNTERS_MARK)
  byNameDone = done
  return byName
end

-- A cast's spell id -> the tracked base id (an aspect or the mark), or nil.
local function resolve(spellID)
  local id = baseSpell(spellID)
  local S = Nock.Spells
  if S.ASPECTS[id] or id == S.HUNTERS_MARK then return id end
  local n = Nock.Flavor.Plain(Nock.API.SpellName(spellID))
  return type(n) == "string" and nameMap()[n] or nil
end

-- `rec` is the aura cache's record when the aspect was read rather than
-- cast: its instance id and icon let a right-click cancel be recognised.
local function setAspect(id, rec)
  local p = Nock.state.player
  if not id then p.aspect = nil; return end
  aspectRec.name, aspectRec.spellId, aspectRec.icon = Nock.API.SpellName(id), id, Nock.API.SpellIcon(id)
  aspectRec.auraInstanceID = rec and rec.auraInstanceID or nil
  aspectRec.auraIcon = rec and rec.icon or nil
  p.aspect = aspectRec
end

local function setMark(expirationTime, duration)
  local t = Nock.state.target
  if not expirationTime then t.huntersMark = nil; return end
  local id = Nock.Spells.HUNTERS_MARK
  markRec.name, markRec.spellId, markRec.icon = Nock.API.SpellName(id), id, Nock.API.SpellIcon(id)
  markRec.expirationTime, markRec.duration = expirationTime, duration
  markRec.remaining = math.max(0, expirationTime - GetTime())
  t.huntersMark = markRec
end

-- Eating / drinking (UI/Frame_ConsumeBanner.lua reads the records): the
-- generic Food / Drink auras by localized name, out of combat only. While
-- auras are secret both clear: no food starts in combat and damage breaks
-- the channel, so a blank pill is right where a stale one would stick.
local eatRec, drinkRec = {}, {}

local function consumeName(id, fallback)
  local n = Nock.Flavor.Plain(Nock.API.SpellName(id))
  return type(n) == "string" and n or fallback
end

-- A cache record -> the reused table, or nil when absent or already expired
-- (a missed removal must not hold the pill up past the channel's own end).
local function consumeRec(rec, out, now)
  if not rec then return nil end
  local exp = rec.expirationTime
  if exp and exp > 0 and exp <= now then return nil end
  out.icon, out.expirationTime, out.duration, out.spellId = rec.icon, exp, rec.duration, rec.spellId
  return out
end

local function setConsume(AC)
  local p = Nock.state.player
  if not AC then p.eating, p.drinking = nil, nil; return end
  local S, now = Nock.Spells, GetTime()
  p.eating   = consumeRec(AC.ByName("player", consumeName(S.FOOD, "Food")), eatRec, now)
  p.drinking = consumeRec(AC.ByName("player", consumeName(S.DRINK, "Drink")), drinkRec, now)
end

-- A cancel by name (`/cancelaura <aspect>` in a macro) fires no cast, and
-- while auras are secret no aura read sees the aspect drop, so the ledger
-- would hold it until combat ends. A post-hook on the cancel clears the
-- aspect when the cancelled name is the one up. The name is the macro's
-- own plain text; "(Rank n)" and case are ignored.
local function cancelledName(spell)
  if type(spell) == "number" then
    spell = Nock.Flavor.Plain(Nock.API.SpellName(spell))
  end
  if type(spell) ~= "string" then return nil end
  spell = spell:gsub("%(.-%)", ""):match("^%s*(.-)%s*$")
  return spell ~= "" and spell:lower() or nil
end

function Auras.OnCancel(spell)
  local a = Nock.state.player.aspect
  if not (a and a.spellId) then return end
  local n = cancelledName(spell)
  if not n then return end
  local cur = Nock.Flavor.Plain(Nock.API.SpellName(a.spellId))
  if type(cur) == "string" and cur:lower() == n then setAspect(nil) end
end

-- The slash command's own entry as a second route, in case the client's
-- /cancelaura does not go through the global CancelSpellByName.
local function onCancelCmd(msg)
  local parse = _G.SecureCmdOptionParse
  if type(msg) ~= "string" or not parse then return end
  local okp, spell = pcall(parse, msg)
  if okp then Auras.OnCancel(spell) end
end

-- Is the buff a buff button describes the aspect record `a`? By instance id
-- when both sides have one (read out of combat), by icon otherwise (an aspect
-- cast in combat; ranks share the icon and no other buff wears it).
function Auras.IsAspectAura(a, inst, icon)
  if not a then return false end
  if inst ~= nil and a.auraInstanceID ~= nil then return inst == a.auraInstanceID end
  return icon ~= nil and (icon == a.auraIcon or icon == a.icon)
end

-- A right-click on the default buff bar runs CancelUnitBuff("player", index,
-- filter); in combat the index alone says nothing, but the button holding it
-- still carries its aura's instance id and icon as plain values (probed
-- 2026-10-06). `frames` is BuffFrame.auraFrames.
function Auras.OnCancelBuff(unit, index, filter, frames)
  local P = Nock.Flavor.Plain
  unit, index, filter = P(unit), P(index), P(filter)
  if unit ~= "player" or type(index) ~= "number" or type(frames) ~= "table" then return end
  if type(filter) == "string" and filter:find("HARMFUL") then return end
  local a = Nock.state.player.aspect
  if not a then return end
  for _, b in ipairs(frames) do
    local info = type(b) == "table" and b.buttonInfo
    if type(info) == "table" and P(info.index) == index then
      local icon = b.Icon and b.Icon.GetTexture and P(b.Icon:GetTexture())
      if Auras.IsAspectAura(a, P(info.auraInstanceID), icon) then setAspect(nil) end
      return
    end
  end
end

local hooked
local function hookCancels()
  if hooked or not _G.hooksecurefunc then return end
  hooked = true
  if _G.CancelSpellByName then hooksecurefunc("CancelSpellByName", Auras.OnCancel) end
  local SC = _G.SecureCmdList
  if type(SC) == "table" and type(SC.CANCELAURA) == "function" then
    hooksecurefunc(SC, "CANCELAURA", onCancelCmd)
  end
  if _G.CancelUnitBuff then
    hooksecurefunc("CancelUnitBuff", function(unit, index, filter)
      local bf = _G.BuffFrame
      Auras.OnCancelBuff(unit, index, filter, bf and bf.auraFrames)
    end)
  end
end

function Auras:OnEnable()
  local p = Nock.state.player
  p.feign, p.dazed, p.eating, p.drinking = nil, nil, nil, nil
  p.sated, p.inLust, p.rapidFire, p.quickShots, p.drums = false, false, false, false, false
  p.canWeave = true
  self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
  self:RegisterEvent("PLAYER_TARGET_CHANGED")
  hookCancels()
end

function Auras:UNIT_SPELLCAST_SUCCEEDED(event, unit, castGUID, spellID)
  if unit ~= "player" or type(spellID) ~= "number" then return end
  local id = resolve(spellID)
  if not id then return end
  local S = Nock.Spells
  if S.ASPECTS[id] then
    setAspect(id)
  elseif id == S.HUNTERS_MARK then
    setMark(GetTime() + S.HUNTERS_MARK_DURATION, S.HUNTERS_MARK_DURATION)
  end
end

-- The mark is per target; a new target has none until it is cast (or read).
function Auras:PLAYER_TARGET_CHANGED()
  setMark(nil)
end

-- Out of combat the cache is the truth and overrides the ledger both ways.
function Auras:Refresh()
  if Nock.Restricted("auras") then setConsume(nil); return end
  local AC = Nock.AuraCache
  setConsume(AC)
  if not AC then return end
  local S = Nock.Spells
  local found, rec
  for id in pairs(S.ASPECTS) do
    rec = AC.BySpell("player", id)
    if rec then found = id; break end
  end
  -- A higher rank's aura carries its own id: find it by name.
  if not found then
    for n, id in pairs(nameMap()) do
      if id ~= S.HUNTERS_MARK then
        rec = AC.ByName("player", n)
        if rec then found = id; break end
      end
    end
  end
  setAspect(found, rec)
  local m = AC.BySpell("target", S.HUNTERS_MARK)
  if not m then
    local hmName = Nock.Flavor.Plain(Nock.API.SpellName(S.HUNTERS_MARK))
    if type(hmName) == "string" then m = AC.ByName("target", hmName) end
  end
  if m then setMark(m.expirationTime or 0, m.duration or 0) else setMark(nil) end
end
