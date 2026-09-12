-- Modules/ProfileShare.lua
-- Profile export/import, the applying half: the current profile out as a
-- string, a string (pasted or bundled) into a NEW named profile, never the one
-- the user is on. AceDB's profile switch fans the change out.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local M = Nock:NewModule("ProfileShare", "AceConsole-3.0")
local PS = Nock.ProfileShare

local function version()
  return (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("Nock", "Version")) or "?"
end

-- min/max per ranged setting, built once by Config/Options.lua; the importer
-- clamps with it.
function M:Ranges()
  return Nock.OptionRanges or {}
end

-- The current profile as a string; opens the copybox unless opts.silent.
function M:Export(opts)
  opts = opts or {}
  local str, why = PS.Pack(Nock.db.profile, Nock.db:GetCurrentProfile(), version(), opts)
  if not str then self:Print("Export failed: " .. tostring(why)); return nil end
  if not opts.silent and Nock.UI and Nock.UI.ShowCopyBox then Nock.UI.ShowCopyBox(str) end
  return str
end

-- Write `clean` into a fresh profile named after `baseName` and switch to it.
-- The profile the user was on is remembered so the Profiles page can offer
-- the way back.
function M:ApplyClean(clean, baseName)
  local existing = {}
  for _, n in ipairs(Nock.db:GetProfiles()) do existing[n] = true end
  local newName = PS.FreeName(baseName or "Imported", existing)
  if Nock.db.char then Nock.db.char.lastOwnProfile = Nock.db:GetCurrentProfile() end
  Nock.db:SetProfile(newName)          -- fresh defaults; OnProfileSwitched fans out
  local p = Nock.db.profile
  for k, v in pairs(clean) do p[k] = v end
  if Nock.OnProfileSwitched then Nock:OnProfileSwitched() end   -- once more, now with the data in
  return newName
end

-- `saveAs` (optional) names the new profile; blank falls back to the name the
-- string carries, which is the sender's and stacks as "Default (2)".
function M:ImportString(text, saveAs)
  local payload, why = PS.Unpack(text)
  if not payload then return nil, why end
  local clean, dropped = PS.Sanitize(payload.profile, Nock.Defaults.profile, self:Ranges())
  local base = (type(saveAs) == "string" and saveAs:match("%S")) and saveAs or payload.name
  local name = self:ApplyClean(clean, base)
  if #dropped > 0 then
    self:Print(("Profile '%s' applied; %d setting(s) from another Nock version were skipped."):format(name, #dropped))
  else
    self:Print(("Profile '%s' applied."):format(name))
  end
  return name
end

function M:Bundled(key)
  for _, b in ipairs(Nock.BundledProfiles or {}) do
    if b.key == key then return b end
  end
  return nil
end

function M:ApplyBundled(key)
  local b = self:Bundled(key)
  if not b then return nil, "no bundled profile '" .. tostring(key) .. "'" end
  return self:ImportString(b.data)
end

-- /nock share export | import <string> | apply <key> | list
function M:Command(arg)
  arg = (arg or ""):gsub("^%s+", "")
  local word, rest = arg:match("^(%S+)%s*(.-)$")
  if word == "export" then
    self:Export()
  elseif word == "import" then
    if rest == "" then
      Nock.UI.ShowPasteBox("Paste a Nock profile string", function(t, saveAs)
        local name, why = self:ImportString(t, saveAs)
        if not name then self:Print("Import failed: " .. tostring(why)) end
      end)
    else
      local name, why = self:ImportString(rest)
      if not name then self:Print("Import failed: " .. tostring(why)) end
    end
  elseif word == "apply" then
    local name, why = self:ApplyBundled(rest)
    if not name then self:Print("Apply failed: " .. tostring(why)) end
  else
    local names = {}
    for _, b in ipairs(Nock.BundledProfiles or {}) do names[#names + 1] = b.key .. " (" .. b.name .. " by " .. b.author .. ")" end
    self:Print("Bundled profiles: " .. (#names > 0 and table.concat(names, ", ") or "none")
      .. ". /nock share export | import <string> | apply <key>")
  end
end
