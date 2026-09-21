-- Core/Flavor.lua
-- Which game this tree is running in (TBC Anniversary vs WoW Forever) and the
-- secret-value guard every shared read goes through on Forever.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")

-- Extra parentheses: select() returns every value from the 4th on, and the
-- 12.x client has two more after the toc number (a base argument to tonumber).
local toc = tonumber((select(4, GetBuildInfo()))) or 0
-- Forever reports WOW_PROJECT_ID == 1 (Mainline), so the interface number is
-- the only runtime signal: 1.60.x packs to 16000..16999; retail is 12xxxx,
-- Era 115xx, Anniversary 205xx (devkit FOREVER.md section 2).
local forever = toc >= 16000 and toc < 20000

local isSecret = _G.issecretvalue

local Flavor = {
  forever = forever,
  toc     = toc,
}

-- nil instead of a secret. A secret number is truthy and survives `or`, but any
-- comparison or arithmetic on it throws; readers that must branch use Plain.
function Flavor.Plain(v)
  if isSecret and v ~= nil and isSecret(v) then return nil end
  return v
end

function Flavor.PlainNumber(v, default)
  v = Flavor.Plain(v)
  if type(v) == "number" then return v end
  return default
end

function Flavor.HudLabel()
  return forever and "Nock HUD" or "React Cluster"
end

Nock.Flavor = Flavor
