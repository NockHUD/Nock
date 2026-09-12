-- Tests/profile_share_test.lua
-- Profile sharing: the two embedded libs load under LuaJIT, the pure
-- pack/unpack round trip, the sanitizer, the export switches, free profile
-- names, and every bundled profile string decoding cleanly against Defaults.
-- Run from the repo root: luajit Tests/profile_share_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end

-- Real LibStub + the two libs (plain Lua 5.1; LibDeflate uses bit ops via the bit library on LuaJIT).
dofile("Libs/LibStub/LibStub.lua")
dofile("Libs/AceSerializer-3.0/AceSerializer-3.0.lua")
dofile("Libs/LibDeflate/LibDeflate.lua")
local LD = LibStub("LibDeflate")
local AS = LibStub("AceSerializer-3.0")
ok(LD and LD.CompressDeflate and LD.EncodeForPrint, "LibDeflate loads")
ok(AS and AS.Serialize, "AceSerializer loads")
local s = AS:Serialize({ a = 1, b = "two", c = { 3 } })
local okd, t = AS:Deserialize(s)
ok(okd and t.a == 1 and t.b == "two" and t.c[1] == 3, "serialize round trip")
local packed = LD:EncodeForPrint(LD:CompressDeflate(s))
ok(LD:DecompressDeflate(LD:DecodeForPrint(packed)) == s, "deflate + print encoding round trip")

--------------------------------------------------------------------------------
-- Core/ProfileShare.lua (pure)
--------------------------------------------------------------------------------
local Nock = {}
local realLibStub = LibStub
local addonStub = { GetAddon = function() return Nock end }
_G.LibStub = setmetatable({}, { __call = function(_, n, s) if n == "AceAddon-3.0" then return addonStub end return realLibStub(n, s) end,
  __index = function(_, k) return realLibStub[k] end })
dofile("Core/ProfileShare.lua")
_G.LibStub = realLibStub
local PS = Nock.ProfileShare

local DEFAULTS = {
  hudEnabled = true, hudMode = "classic", scale = 1.0, locked = true,
  position = false, elementPositions = {}, castBarPosition = false,
  warningsPosition = false, helpersPosition = false,
  weaveBindMacroDown = "/use Raptor Strike", weaveBindMacroUp = "/use !Auto Shot", weaveBindEnabled = false,
  buffTrackerCustomPlayer = "", warnColor = { 1, 0, 0, 1 }, mailboxNames = {},
  debuffTrackerCols = 8,
}
local profile = {
  hudEnabled = false, hudMode = "react", scale = 1.2, locked = false,
  position = { point = "CENTER", relPoint = "CENTER", x = 10, y = -20 },
  elementPositions = { Steady = { point = "TOP", relPoint = "TOP", x = 0, y = 0 } },
  castBarPosition = false,
  weaveBindMacroDown = "/use Snowball", weaveBindMacroUp = "/use KC", weaveBindEnabled = true,
  warnColor = { 0, 1, 0, 1 }, mailboxNames = { "a", "b" }, debuffTrackerCols = 99,
}

-- Strip: switches drop exactly their keys
local s1 = PS.Strip(profile, { positions = false })
ok(s1.position == nil and s1.elementPositions == nil and s1.castBarPosition == nil and s1.hudMode == "react", "positions off: every *Position + elementPositions gone")
local s2 = PS.Strip(profile, { macros = false })
ok(s2.weaveBindMacroDown == nil and s2.weaveBindEnabled == nil and s2.position ~= nil, "macros off: weaveBind* gone, positions kept")
local s3 = PS.Strip(profile, {})
ok(s3.position ~= profile.position and s3.position.x == 10, "strip deep-copies")
local s4 = PS.Strip({ hudMode = "react", profilerOverlayShown = true, profilerOverlayPos = { "TOP" }, mdCastDebug = true }, {})
ok(s4.hudMode == "react" and s4.profilerOverlayShown == nil and s4.profilerOverlayPos == nil and s4.mdCastDebug == nil,
   "strip: session/debug flags never leave, whatever the switches")
local c4, d4 = PS.Sanitize({ hudMode = "react", profilerOverlayShown = true, mdCastDebug = true },
  { hudMode = "classic", profilerOverlayShown = false, mdCastDebug = false }, {})
ok(c4.hudMode == "react" and c4.profilerOverlayShown == nil and c4.mdCastDebug == nil and #d4 == 0,
   "sanitize: session/debug flags in an old string are skipped silently")

-- Pack / Unpack round trip
local str = PS.Pack(profile, "Yaxal", "2.0.0-alpha.2", {})
ok(type(str) == "string" and str:sub(1, #PS.HEADER) == PS.HEADER, "packed string carries the header")
local payload, why = PS.Unpack(str)
ok(payload and payload.v == 1 and payload.name == "Yaxal" and payload.nock == "2.0.0-alpha.2", "unpack: envelope")
ok(payload and payload.profile.hudMode == "react" and payload.profile.position.y == -20, "unpack: profile data intact")
ok(select(2, PS.Unpack("hello")) == "not a Nock profile string", "unpack: header check")
ok(select(2, PS.Unpack(PS.HEADER .. "%%%")) == "corrupt string", "unpack: corrupt body")
local future = PS.Pack(profile, "x", "9.9.9", {}):gsub("^" .. PS.HEADER, "NOCK9:")
ok(select(2, PS.Unpack(future)) == "not a Nock profile string", "unpack: unknown header version")

-- Sanitize
local clean, dropped = PS.Sanitize({
  hudMode = "react", scale = "big", unknownKey = 1, position = { point = "CENTER", relPoint = "CENTER", x = 1, y = 2 },
  castBarPosition = "nope", warnColor = { 0, 1, 0, 1 }, mailboxNames = { "a", 2 }, debuffTrackerCols = 99,
  evil = function() end, locked = true,
}, DEFAULTS, { debuffTrackerCols = { 1, 12 } })
ok(clean.hudMode == "react" and clean.locked == true, "sanitize keeps typed matches")
ok(clean.scale == nil and clean.unknownKey == nil and clean.evil == nil, "sanitize drops wrong type, unknown key, function")
ok(clean.position and clean.position.x == 1 and clean.castBarPosition == nil, "false-default accepts a table, not a string")
ok(clean.warnColor and clean.warnColor[2] == 1, "colour tables pass")
ok(clean.mailboxNames and #clean.mailboxNames == 2, "string/number lists pass")
ok(clean.debuffTrackerCols == 12, "ranged number clamped")
ok(#dropped == 4, "four drops reported (" .. table.concat(dropped, "; ") .. ")")

-- FreeName
ok(PS.FreeName("Yaxal", {}) == "Yaxal", "free name: base free")
ok(PS.FreeName("Yaxal", { Yaxal = true }) == "Yaxal (2)", "free name: (2)")
ok(PS.FreeName("Yaxal", { Yaxal = true, ["Yaxal (2)"] = true }) == "Yaxal (3)", "free name: (3)")

--------------------------------------------------------------------------------
-- Modules/ProfileShare.lua: apply into a NEW profile, never the current one
--------------------------------------------------------------------------------
do
  local profiles = { Default = { hudMode = "classic", scale = 1 } }
  local current = "Default"
  local M
  Nock.Defaults = { profile = DEFAULTS }
  Nock.db = {
    char = {},
    GetProfiles = function() local out = {} for k in pairs(profiles) do out[#out + 1] = k end return out end,
    GetCurrentProfile = function() return current end,
    SetProfile = function(_, name)
      current = name
      profiles[name] = profiles[name] or {}
      for k, v in pairs(DEFAULTS) do if profiles[name][k] == nil then profiles[name][k] = type(v) == "table" and {} or v end end
      Nock.db.profile = profiles[name]
      if Nock.OnProfileSwitched then Nock:OnProfileSwitched() end
    end,
  }
  Nock.db.profile = profiles.Default
  local msgs = {}
  function Nock:SendMessage(m) msgs[#msgs + 1] = m end
  function Nock:NewModule(name) M = { name = name, Print = function() end, RegisterMessage = function() end }; return M end
  function Nock:GetModule() return nil end
  Nock.UI = { ShowCopyBox = function(t) Nock._lastCopy = t end }
  Nock.BundledProfiles = {}
  _G.C_AddOns = { GetAddOnMetadata = function() return "2.0.0-alpha.2" end }
  _G.LibStub = setmetatable({}, { __call = function(_, n, s) if n == "AceAddon-3.0" then return addonStub end return realLibStub(n, s) end })
  dofile("Modules/ProfileShare.lua")
  _G.LibStub = realLibStub

  local str = M:Export({ silent = true })
  ok(type(str) == "string" and str:sub(1, 6) == "NOCK1:", "Export packs the current profile")
  local name, why = M:ImportString(str)
  ok(name == "Default (2)", "import lands in a NEW profile named after the source (" .. tostring(name or why) .. ")")
  ok(current == "Default (2)" and profiles.Default.hudMode == "classic", "switched to it; the original untouched")
  ok(Nock.db.char.lastOwnProfile == "Default", "the previous profile is remembered")
  ok(M:ImportString(str, "Raid night") == "Raid night", "a Save-as name overrides the string's name")
  ok(M:ImportString(str, "   ") == "Default (3)", "a blank Save-as falls back to the string's name")
  local n2, w2 = M:ImportString("garbage")
  ok(n2 == nil and w2 == "not a Nock profile string", "bad string refused with the reason")

  Nock.BundledProfiles = { { key = "yaxal", name = "Yaxal", author = "Yaxal", version = "2.0.0-alpha.2", blurb = "x",
    data = PS.Pack({ hudMode = "react" }, "Yaxal", "2.0.0-alpha.2", {}) } }
  ok(M:ApplyBundled("yaxal") == "Yaxal" and profiles.Yaxal.hudMode == "react", "bundled apply: new profile from the string")
  ok(M:ApplyBundled("yaxal") == "Yaxal (2)", "bundled apply again: a copy, never an overwrite")
  ok(select(2, M:ApplyBundled("nope")) == "no bundled profile 'nope'", "unknown bundled key refused")
end

--------------------------------------------------------------------------------
-- Config/ProfilesBundled.lua: every bundled string decodes and sanitizes clean
--------------------------------------------------------------------------------
do
  -- A second addon table with the real Constants + Defaults, so the check is
  -- against what ships, not the toy DEFAULTS above.
  local real = { state = {} }
  local realStub = { GetAddon = function() return real end }
  _G.LibStub = setmetatable({}, { __call = function(_, n, s) if n == "AceAddon-3.0" then return realStub end return realLibStub(n, s) end })
  dofile("Core/Constants.lua")
  dofile("Config/Defaults.lua")
  dofile("Config/ProfilesBundled.lua")
  _G.LibStub = realLibStub
  ok(type(real.BundledProfiles) == "table", "bundled list exists")
  ok(type(real.Defaults.profile.position) == "table", "real Defaults loaded")
  for _, b in ipairs(real.BundledProfiles) do
    ok(type(b.key) == "string" and type(b.name) == "string" and type(b.author) == "string" and type(b.version) == "string" and type(b.data) == "string", "bundle '" .. tostring(b.key) .. "': fields")
    local payload, why = PS.Unpack(b.data)
    ok(payload ~= nil, "bundle '" .. tostring(b.key) .. "' decodes (" .. tostring(why) .. ")")
    if payload then
      local _, dropped = PS.Sanitize(payload.profile, real.Defaults.profile, {})
      ok(#dropped == 0, "bundle '" .. b.key .. "' is clean against Defaults (" .. table.concat(dropped, "; ") .. ")")
      local leak = {}
      for k in pairs(PS.NEVER_SHARED) do if payload.profile[k] ~= nil then leak[#leak + 1] = k end end
      ok(#leak == 0, "bundle '" .. b.key .. "' carries no session/debug flag (" .. table.concat(leak, ", ") .. ")")
      -- A bundle is a diff from Defaults, so a changed default reaches it too.
      local same = {}
      for k, v in pairs(payload.profile) do
        local d = real.Defaults.profile[k]
        if type(v) ~= "table" and v == d then same[#same + 1] = k end
      end
      ok(#same == 0, "bundle '" .. b.key .. "' carries no default-equal scalar (" .. table.concat(same, ", ") .. ")")
    end
  end
  -- The real Defaults survive a pack/unpack/sanitize round trip with nothing dropped.
  local rt = PS.Unpack(PS.Pack(real.Defaults.profile, "Defaults", "x", {}))
  local _, dropped = PS.Sanitize(rt.profile, real.Defaults.profile, {})
  ok(#dropped == 0, "the shipped Defaults round-trip clean (" .. table.concat(dropped, "; ") .. ")")
end

print(string.format("%d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
