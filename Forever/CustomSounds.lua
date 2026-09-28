-- Forever/CustomSounds.lua
-- The user's own sounds: resolve what they typed to a playable path or FileDataID and register each into LibSharedMedia.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local CS = {}
Nock.CustomSounds = CS

-- Tested in-game on Forever (2026-09-28): any folder under Interface\AddOns
-- plays, with or without a .toc; Interface\Sounds and anything outside the
-- game never do. A folder of its own survives Nock updates.
CS.FOLDER = "Interface\\AddOns\\NockSounds\\"
-- LSM ignores a key that already exists: the prefix keeps a user's "Ping"
-- from colliding with SharedMedia's and groups the entries in the pickers.
CS.PREFIX = "Custom: "
CS.NAME_MAX = 32

CS.MSG = {
  EMPTY     = "Type a file name, a path or a sound id.",
  OUTSIDE   = "Only files inside Interface\\AddOns can play.",
  FORMAT    = "Only .ogg and .mp3 files can play.",
  NO_NAME   = "Give the sound a name.",
  LONG_NAME = "Names are 32 characters at most.",
  DUP_NAME  = "You already have a sound with that name.",
  STALE     = "That name held another sound this session; /reload before reusing it, or pick another name.",
  NOT_FOUND = "Not found. Check the name, and fully restart the game after adding a file.",
}

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

function CS.Resolve(source)
  if type(source) == "number" then
    if source > 0 then return source end
    return nil, CS.MSG.EMPTY
  end
  if type(source) ~= "string" then return nil, CS.MSG.EMPTY end
  -- Explorer's "Copy as path" wraps the path in quotes.
  local s = trim((trim(source):gsub('^"(.*)"$', "%1")))
  if s == "" then return nil, CS.MSG.EMPTY end
  if s:match("^%d+$") then
    local id = tonumber(s)
    if id and id > 0 then return id end
    return nil, CS.MSG.EMPTY
  end
  s = s:gsub("/", "\\")
  local at = s:lower():find("interface\\", 1, true)
  if at then
    s = s:sub(at)
  elseif s:find(":", 1, true) or s:sub(1, 1) == "\\" then
    return nil, CS.MSG.OUTSIDE
  else
    -- The intro names the folder, so "NockSounds\ding.mp3" and
    -- "AddOns\NockSounds\ding.mp3" are natural to type: never double it.
    local rel = s
    if rel:lower():sub(1, 7) == "addons\\" then rel = rel:sub(8) end
    if rel:lower():sub(1, 11) == "nocksounds\\" then
      s = CS.FOLDER .. rel:sub(12)
    elseif rel ~= s then
      s = "Interface\\AddOns\\" .. rel
    else
      s = CS.FOLDER .. s
    end
  end
  local low = s:lower()
  if low:sub(1, 17) ~= "interface\\addons\\" then return nil, CS.MSG.OUTSIDE end
  if not (low:match("%.ogg$") or low:match("%.mp3$")) then return nil, CS.MSG.FORMAT end
  return s
end

function CS.Validate(name, source, list, lsm)
  local n = type(name) == "string" and trim(name) or ""
  if n == "" then return nil, CS.MSG.NO_NAME end
  if #n > CS.NAME_MAX then return nil, CS.MSG.LONG_NAME end
  if type(list) == "table" then
    for _, e in ipairs(list) do
      if type(e) == "table" and type(e.name) == "string" and trim(e.name):lower() == n:lower() then
        return nil, CS.MSG.DUP_NAME
      end
    end
  end
  local v, err = CS.Resolve(source)
  if not v then return nil, err end
  -- LSM cannot overwrite: a name removed and re-added this session would
  -- keep playing its old sound until a /reload.
  if lsm and lsm.Fetch then
    local held = lsm:Fetch("sound", CS.PREFIX .. n, true)
    if held ~= nil and held ~= v then return nil, CS.MSG.STALE end
  end
  return v
end

function CS.RegisterAll(list, lsm)
  if type(list) ~= "table" or not (lsm and lsm.Register) then return 0 end
  local count = 0
  for _, e in ipairs(list) do
    local name = type(e) == "table" and type(e.name) == "string" and trim(e.name) or ""
    local v = name ~= "" and CS.Resolve(e.source)
    if v and lsm:Register("sound", CS.PREFIX .. name, v) then count = count + 1 end
  end
  return count
end

-- Plays the resolved source once. Only an explicit willPlay == false (or a
-- throw) counts as missing: an unconfirmed nil is given the benefit.
function CS.Test(source, channel, playFile)
  local v, err = CS.Resolve(source)
  if not v then return false, err end
  local okp, willPlay = pcall(playFile, v, channel or "Master")
  if not okp or willPlay == false then return false, CS.MSG.NOT_FOUND end
  return true
end

-- Register the saved list once the db exists (module OnInitialize runs after
-- the addon's, which creates Nock.db). Adds made in the settings register
-- themselves (Config/Options.lua); the pickers read LSM when they open.
local Module = Nock:NewModule("CustomSounds")

function Module:OnInitialize()
  local g = Nock.db and Nock.db.global
  CS.RegisterAll(g and g.customSounds, LibStub("LibSharedMedia-3.0", true))
end
