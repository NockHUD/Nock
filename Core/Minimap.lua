-- Core/Minimap.lua
-- The minimap button: a LibDataBroker launcher (the Nock mark) registered
-- with LibDBIcon. Left-click opens the settings, right-click toggles the
-- global lock; profile.minimap is LibDBIcon's own store (hide, minimapPos).

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")

local LDB    = LibStub("LibDataBroker-1.1", true)
local DBIcon = LibStub("LibDBIcon-1.0", true)

local NAME = "Nock"
local ICON = "Interface\\AddOns\\Nock\\Media\\NockMark"   -- white mark on transparent, 128 px

local function minimapDB()
  local p = Nock.db and Nock.db.profile
  if not p then return nil end
  if type(p.minimap) ~= "table" then p.minimap = { hide = false } end
  return p.minimap
end

-- Registered once, from OnInitialize — for every character, the banker alt
-- included (it opens the settings there too). Idempotent.
function Nock:SetupMinimapIcon()
  if self._ldbObject or not (LDB and DBIcon) then return end
  local db = minimapDB()
  if not db then return end
  local addon = self
  self._ldbObject = LDB:NewDataObject(NAME, {
    type = "launcher",
    text = NAME,
    icon = ICON,
    OnClick = function(_, button)
      if button == "RightButton" then
        addon:SetLocked(not addon.IsLocked())
      else
        addon:OpenConfig()
      end
    end,
    OnTooltipShow = function(tt)
      tt:AddLine(("Nock v%s"):format(addon.version or (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(NAME, "Version")) or "?"))
      tt:AddLine(("Frames are %s."):format(addon.IsLocked() and "locked" or "UNLOCKED"), 0.8, 0.8, 0.8)
      tt:AddLine(" ")
      tt:AddLine("|cffffd200Left-click|r  Settings", 1, 1, 1)
      tt:AddLine("|cffffd200Right-click|r  Lock / unlock all frames", 1, 1, 1)
    end,
  })
  DBIcon:Register(NAME, self._ldbObject, db)
end

-- After a profile switch: point LibDBIcon at the new profile's table.
function Nock:ApplyMinimapIcon()
  if not (DBIcon and self._ldbObject) then return end
  local db = minimapDB()
  if db then DBIcon:Refresh(NAME, db) end
end

function Nock:SetMinimapShown(shown)
  local db = minimapDB()
  if not db then return end
  db.hide = not shown
  if not (DBIcon and self._ldbObject) then return end
  if shown then DBIcon:Show(NAME) else DBIcon:Hide(NAME) end
end

function Nock:IsMinimapShown()
  local db = minimapDB()
  return db ~= nil and not db.hide
end
