-- UI/SettingsLauncher.lua
-- The Blizzard AddOns panel entry (one button into the settings window) and the window's skinned confirm popup.
--
-- `Settings` here is Blizzard's settings API, never Nock's module: this file
-- reaches the window only through Nock.Settings.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
Nock.UI = Nock.UI or {}
local Skin = Nock.Skin

-- Interface -> AddOns -> Nock: a short panel with one primary button. The
-- legacy AceConfig dialog stays reachable behind a ghost button for anyone
-- who needs the old tree while the window is young.
function Nock.UI.RegisterSettingsLauncher()
  local panel = CreateFrame("Frame", "NockSettingsLauncher")
  panel.name = "Nock"
  local title = panel:CreateFontString(nil, "OVERLAY")
  Skin.Font(title, "displayMedium", 30); Skin.Text(title, "ink")
  title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16); title:SetText("NOCK")
  local sub = panel:CreateFontString(nil, "OVERLAY")
  Skin.Font(sub, "ui", 13); Skin.Text(sub, "ink2")
  sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
  sub:SetText("Nock's settings live in their own window. /nock opens it too.")
  local open = Skin.Button(panel, "Open Nock settings", "primary", 200, 32)
  open:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -16)
  open:SetScript("OnClick", function()
    -- the fullscreen Blizzard panel would otherwise sit over the window
    if SettingsPanel and SettingsPanel:IsShown() and HideUIPanel then HideUIPanel(SettingsPanel)
    elseif InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() and HideUIPanel then HideUIPanel(InterfaceOptionsFrame) end
    if Nock.Settings and Nock.Settings.Open then Nock.Settings:Open() end
  end)
  local legacy = Skin.Button(panel, "Legacy dialog", "ghost", nil, 32)
  legacy:SetPoint("LEFT", open, "RIGHT", 10, 0)
  legacy:SetScript("OnClick", function()
    local dialog = LibStub("AceConfigDialog-3.0", true)
    if dialog then dialog:Open("Nock") end
  end)
  if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    local cat = Settings.RegisterCanvasLayoutCategory(panel, "Nock")
    Settings.RegisterAddOnCategory(cat)
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
  end
  return panel
end

-- Confirm popup in the skin: raised panel above the window, the text, Yes /
-- No, ESC = No. One frame, re-bound per ask.
local pop
Nock.UI.SettingsPopup = {}
function Nock.UI.SettingsPopup.Confirm(textStr, onYes)
  if not pop then
    pop = CreateFrame("Frame", "NockSettingsConfirm", UIParent)
    pop:SetFrameStrata("DIALOG"); pop:SetToplevel(true)
    pop:SetSize(380, 120); pop:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    Skin.Surface(pop, "raised", "line")
    pop:EnableMouse(true)
    pop.text = pop:CreateFontString(nil, "OVERLAY")
    Skin.Font(pop.text, "ui", 13); Skin.Text(pop.text, "ink")
    pop.text:SetPoint("TOPLEFT", pop, "TOPLEFT", 20, -20); pop.text:SetPoint("TOPRIGHT", pop, "TOPRIGHT", -20, -20)
    pop.text:SetJustifyH("LEFT"); pop.text:SetWordWrap(true)
    pop.yes = Skin.Button(pop, "Yes", "primary", 80, 30); pop.yes:SetPoint("BOTTOMRIGHT", pop, "BOTTOMRIGHT", -20, 16)
    pop.no = Skin.Button(pop, "No", "ghost", 80, 30); pop.no:SetPoint("RIGHT", pop.yes, "LEFT", -8, 0)
    pop.no:SetScript("OnClick", function() pop:Hide() end)
    pop.yes:SetScript("OnClick", function() pop:Hide(); local fn = pop.onYes; pop.onYes = nil; if fn then fn() end end)
    tinsert(UISpecialFrames, "NockSettingsConfirm")
  end
  pop.text:SetText(textStr or "")
  pop:SetHeight(20 + (pop.text:GetStringHeight() or 16) + 62)
  pop.onYes = onYes
  pop:Show()
end
