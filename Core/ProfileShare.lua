-- Core/ProfileShare.lua
-- Profile export/import, the pure half: pack a profile table into a print-safe
-- string, unpack one, strip by switch, sanitize against Defaults, pick a free
-- profile name. Nothing here touches AceDB or a frame; Modules/ProfileShare.lua
-- applies the result.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local PS = {}
Nock.ProfileShare = PS

PS.HEADER = "NOCK1:"

local function deflate()    return LibStub("LibDeflate", true) end
local function serializer() return LibStub("AceSerializer-3.0", true) end

local function deepCopy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = deepCopy(x) end
  return out
end

-- `position` (the HUD box), `elementPositions` (the free-layout rows) and
-- every `<frame>Position` key.
local function isPositionKey(k)
  if type(k) ~= "string" then return false end
  return k == "position" or k == "elementPositions" or k:match("Position$") ~= nil
end
local function isMacroKey(k)
  return type(k) == "string" and k:sub(1, 9) == "weaveBind"
end
-- Session and troubleshooting flags never travel, in or out: a profiler
-- overlay or a debug print switched on for one session must not come back
-- on for whoever applies the string (the author's export carried the
-- overlay, 2026-09-12).
PS.NEVER_SHARED = { profilerOverlayShown = true, profilerOverlayPos = true, mdCastDebug = true }

-- Deep copy minus the keys a switched-off export switch drops.
function PS.Strip(profile, opts)
  opts = opts or {}
  local out = {}
  for k, v in pairs(profile or {}) do
    local drop = PS.NEVER_SHARED[k] or (opts.positions == false and isPositionKey(k)) or (opts.macros == false and isMacroKey(k))
    if not drop then out[k] = deepCopy(v) end
  end
  return out
end

function PS.Pack(profile, name, version, opts)
  local AS, LD = serializer(), deflate()
  if not (AS and LD) then return nil, "libraries missing" end
  local payload = { v = 1, nock = tostring(version or "?"), name = tostring(name or "Profile"), profile = PS.Strip(profile, opts) }
  local raw = AS:Serialize(payload)
  return PS.HEADER .. LD:EncodeForPrint(LD:CompressDeflate(raw, { level = 9 }))
end

function PS.Unpack(text)
  local AS, LD = serializer(), deflate()
  if not (AS and LD) then return nil, "libraries missing" end
  if type(text) ~= "string" then return nil, "not a Nock profile string" end
  text = text:gsub("^%s+", ""):gsub("%s+$", "")
  if text:sub(1, #PS.HEADER) ~= PS.HEADER then return nil, "not a Nock profile string" end
  local body = LD:DecodeForPrint(text:sub(#PS.HEADER + 1))
  local raw = body and LD:DecompressDeflate(body)
  if not raw then return nil, "corrupt string" end
  local okd, payload = AS:Deserialize(raw)
  if not okd or type(payload) ~= "table" or type(payload.profile) ~= "table" then return nil, "corrupt string" end
  if payload.v ~= 1 then return nil, "unsupported version" end
  return payload
end

-- A list default ({}) takes any array/map of plain values (strings, numbers,
-- booleans, nested plain tables); anything executable fails it.
local function listOk(v)
  for _, x in pairs(v) do
    local t = type(x)
    if t ~= "string" and t ~= "number" and t ~= "table" and t ~= "boolean" then return false end
  end
  return true
end

-- A value fits its default: same Lua type, with two relaxations -- a `false`
-- default also takes a table (positions), an empty-table default takes a list
-- of plain values. Ranged numbers are clamped when `ranges[key] = {min, max}`.
function PS.Sanitize(profile, defaults, ranges)
  local clean, dropped = {}, {}
  ranges = ranges or {}
  for k, v in pairs(profile or {}) do
    local d = defaults[k]
    local tv, td = type(v), type(d)
    if PS.NEVER_SHARED[k] then
      -- skipped silently: a string from before the rule may still carry them
    elseif d == nil then
      dropped[#dropped + 1] = tostring(k) .. ": unknown setting"
    elseif tv == "function" or tv == "userdata" or tv == "thread" then
      dropped[#dropped + 1] = tostring(k) .. ": not data"
    elseif td == "boolean" and d == false and tv == "table" then
      clean[k] = deepCopy(v)                      -- a position, or another false|table key
    elseif td == "table" and tv == "table" then
      if listOk(v) then clean[k] = deepCopy(v) else dropped[#dropped + 1] = tostring(k) .. ": bad list" end
    elseif tv == td then
      if tv == "number" and ranges[k] then
        local lo, hi = ranges[k][1], ranges[k][2]
        if lo and v < lo then v = lo end
        if hi and v > hi then v = hi end
      end
      clean[k] = v
    else
      dropped[#dropped + 1] = tostring(k) .. ": expected " .. td .. ", got " .. tv
    end
  end
  return clean, dropped
end

function PS.FreeName(base, existing)
  if not existing[base] then return base end
  local n = 2
  while existing[base .. " (" .. n .. ")"] do n = n + 1 end
  return base .. " (" .. n .. ")"
end
