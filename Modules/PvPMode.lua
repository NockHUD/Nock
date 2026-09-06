-- Modules/PvPMode.lua
-- PvP mode: the one reading (state.player.pvp) from the profile's pvpMode, the zone and the world flag; roster classes; /nock pvp.
--
-- Battlegrounds and arenas are a different game (no consumables, no raid
-- tools, the PvP trinket is the right trinket). This module only decides
-- whether the mode is on and says so; every consumer (the trackers, the
-- warnings, the aggro flash, the weave bind, the debuff set) reads
-- state.player.pvp and its own pvp* switch. Nothing else detects PvP.
--
-- It also keeps state.group.classes (engine tokens of everyone in your
-- party or raid, you included) for the debuff tracker's class filter.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local PvPMode = Nock:NewModule("PvPMode", "AceEvent-3.0", "AceConsole-3.0")

local MODE_NAMES = { off = "off", on = "on", auto = "auto (battlegrounds and arenas)" }

local function profile()
  return Nock.db and Nock.db.profile or nil
end

local function instanceType()
  if not IsInInstance then return nil end
  local _, t = IsInInstance()
  return t
end

local function worldFlagged()
  if UnitIsPVPFreeForAll and UnitIsPVPFreeForAll("player") then return true end
  if UnitIsPVP and UnitIsPVP("player") then return true end
  return false
end

-- Recompute the reading; on a flip, tell everyone. `quiet` skips the chat line
-- (the slash command prints its own).
function PvPMode:Evaluate(_, quiet)
  local p = profile()
  local st = Nock.state and Nock.state.player
  if not (p and st) then return end
  local active = Nock.PvPActive(p, instanceType(), worldFlagged())
  if active == (st.pvp == true) then return end
  st.pvp = active
  self:SendMessage("NOCK_PVP_CHANGED", active)
  self:SendMessage("NOCK_VISUALS_CHANGED")
  local reg = LibStub("AceConfigRegistry-3.0", true)
  if reg then reg:NotifyChange("Nock") end
  if quiet ~= true then self:Print(active and "PvP mode ON." or "PvP mode OFF.") end
end

local UNITS = { "player" }
for i = 1, 4  do UNITS[#UNITS + 1] = "party" .. i end
for i = 1, 40 do UNITS[#UNITS + 1] = "raid" .. i end

-- Classes present in the group, engine tokens -> true. Replaced (never
-- mutated in place) and announced only when the set actually changes, so a
-- 40-man battleground filling up does not repaint anything forty times.
function PvPMode:ScanRoster()
  local g = Nock.state and Nock.state.group
  if not (g and UnitClass) then return end
  local seen = {}
  for _, u in ipairs(UNITS) do
    if not UnitExists or UnitExists(u) then
      local _, cls = UnitClass(u)
      if cls then seen[cls] = true end
    end
  end
  if not Nock.ClassSetChanged(g.classes, seen) then return end
  g.classes = seen
  self:SendMessage("NOCK_GROUP_CLASSES_CHANGED")
end

-- /nock pvp [on|off|auto]: no argument toggles between on and off.
function PvPMode:Slash(arg)
  local p = profile()
  if not p then return end
  arg = (arg or ""):match("^%s*(.-)%s*$")
  if arg == "on" or arg == "off" or arg == "auto" then
    p.pvpMode = arg
  elseif arg == "" then
    p.pvpMode = (Nock.state.player.pvp == true) and "off" or "on"
  else
    self:Print("Usage: /nock pvp [on|off|auto]")
    return
  end
  self:Evaluate(nil, true)
  local reg = LibStub("AceConfigRegistry-3.0", true)
  if reg then reg:NotifyChange("Nock") end
  self:Print(("PvP mode %s (setting: %s)."):format(Nock.state.player.pvp and "ON" or "OFF", MODE_NAMES[p.pvpMode] or p.pvpMode))
end

function PvPMode:OnWorld()
  self:Evaluate()
  self:ScanRoster()
end

function PvPMode:OnFlags(_, unit)
  if unit == "player" then self:Evaluate() end
end

function PvPMode:OnEnable()
  self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnWorld")
  self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "Evaluate")
  self:RegisterEvent("UPDATE_BATTLEFIELD_STATUS", "Evaluate")
  self:RegisterEvent("PLAYER_FLAGS_CHANGED", "OnFlags")
  self:RegisterEvent("GROUP_ROSTER_UPDATE", "ScanRoster")
  -- An Options edit of the mode sends this; Evaluate is a no-op without a flip.
  self:RegisterMessage("NOCK_VISUALS_CHANGED", "Evaluate")
  self:OnWorld()
end
