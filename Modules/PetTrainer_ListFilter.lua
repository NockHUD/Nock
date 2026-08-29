-- Modules/PetTrainer_ListFilter.lua
-- Filters Blizzard's Beast Training craft list to the active preset's remaining
-- to-dos (CraftFrame_Update hook + row re-render, the mechanism proven by
-- MalfUI_BeastTrainingFilter) with auto-advance. Second file of the PetTrainer
-- module; PetTrainer.lua invokes the ListFilter_* methods defined here.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local PetTrainer = Nock:GetModule("PetTrainer")
local C = Nock.Constants

local installed = false   -- hook is in place
local standDown = false   -- permanently disabled this session (MalfUI / missing globals)
local checked = false     -- install attempt already made

-- Blizzard globals the re-render depends on. Missing any -> soft-disable.
local REQUIRED = {
  "CraftFrame_Update", "CraftFrame_SetSelection", "GetCraftSelectionIndex",
  "FauxScrollFrame_Update", "FauxScrollFrame_GetOffset",
  "CRAFTS_DISPLAYED", "CRAFT_SKILL_HEIGHT",
  "CraftTypeColor", "Craft_SetSubTextColor",
  "CraftListScrollFrame", "CraftHighlightFrame", "CraftExpandButtonFrame",
  "Craft1",
}

local beastTrainingName
local function isPetTraining()
  if CraftIsPetTraining then return CraftIsPetTraining() end
  if not beastTrainingName then
    if C_Spell and C_Spell.GetSpellInfo then
      local info = C_Spell.GetSpellInfo(C.SpellID.BEAST_TRAINING)
      beastTrainingName = type(info) == "table" and info.name or info
    elseif GetSpellInfo then
      beastTrainingName = GetSpellInfo(C.SpellID.BEAST_TRAINING)
    end
  end
  return GetCraftName and beastTrainingName ~= nil and GetCraftName() == beastTrainingName
end

local function profileGet(key, fallback)
  local p = Nock.db and Nock.db.profile
  if p and p[key] ~= nil then return p[key] end
  return fallback
end

-- All conditions under which we repaint the list. Any failure -> Blizzard's
-- own rendering stands untouched.
local function filterActive()
  if not installed then return false end
  if profileGet("petTrainerHelperEnabled", true) == false then return false end
  if profileGet("petTrainerListFilter", true) == false then return false end
  if not CraftFrame or not CraftFrame:IsShown() then return false end
  return isPetTraining()
end

local emptyMsg
local function setEmptyMessage(overCount)
  if not emptyMsg then
    emptyMsg = CraftFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    emptyMsg:SetPoint("TOP", CraftListScrollFrame, "TOP", 0, -40)
    emptyMsg:SetWidth(260)
  end
  if overCount and overCount > 0 then
    emptyMsg:SetText(("Preset complete - nothing to train.\n(%d over target - needs untraining)"):format(overCount))
  else
    emptyMsg:SetText("Preset complete - nothing to train.")
  end
  emptyMsg:Show()
end
local function hideEmptyMessage()
  if emptyMsg then emptyMsg:Hide() end
end

-- Repaint Blizzard's row buttons from the todo set. Runs after every
-- CraftFrame_Update, so Blizzard has already fully drawn the frame; we only
-- re-fill the rows, scrollbar, and selection highlight.
local function renderFilteredList()
  local todos, over = PetTrainer:GetTodoCraftIndices()
  local numRows = #todos
  FauxScrollFrame_Update(CraftListScrollFrame, numRows, CRAFTS_DISPLAYED,
    CRAFT_SKILL_HEIGHT, nil, nil, nil, CraftHighlightFrame, 293, 316)
  local offset = FauxScrollFrame_GetOffset(CraftListScrollFrame)
  CraftHighlightFrame:Hide()
  CraftExpandButtonFrame:Hide()

  for i = 1, CRAFTS_DISPLAYED do
    local button = _G["Craft" .. i]
    local todo = todos[i + offset]
    if todo and button then
      local name, sub, ctype, _, _, tp = GetCraftInfo(todo.craftIndex)
      local color = CraftTypeColor[ctype] or CraftTypeColor["available"]
      local text = _G["Craft" .. i .. "Text"]
      local subText = _G["Craft" .. i .. "SubText"]
      local cost = _G["Craft" .. i .. "Cost"]
      button:SetNormalTexture("")
      _G["Craft" .. i .. "Highlight"]:SetTexture("")
      text:SetPoint("TOPLEFT", button, "TOPLEFT", 3, 0)
      if CraftListScrollFrame:IsShown() then
        button:SetWidth(293)
      else
        button:SetWidth(323)
      end
      button:SetNormalFontObject(color.font)
      Craft_SetSubTextColor(button, color.r, color.g, color.b)
      cost:SetTextColor(color.r, color.g, color.b)
      button:SetText(" " .. (name or ""))
      if sub and sub ~= "" then
        subText:SetText(("(%s)"):format(sub))
      else
        subText:SetText("")
      end
      if tp and tp > 0 then
        cost:SetText(("(%d TP)"):format(tp))
      else
        cost:SetText("")
      end
      subText:SetPoint("LEFT", text, "RIGHT", 10, 0)
      button:SetID(todo.craftIndex)
      button:Show()
      if GetCraftSelectionIndex() == todo.craftIndex then
        CraftHighlightFrame:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
        CraftHighlightFrame:Show()
        Craft_SetSubTextColor(button, 1.0, 1.0, 1.0)
        cost:SetTextColor(1.0, 1.0, 1.0)
        button:LockHighlight()
      else
        button:UnlockHighlight()
      end
    elseif button then
      button:Hide()
    end
  end

  if numRows == 0 then setEmptyMessage(over) else hideEmptyMessage() end
end

-- Auto-advance: one frame after any update, select the first todo if the
-- current selection isn't one (fires CRAFT_UPDATE -> re-render; terminates
-- because the new selection IS a todo). Stub until Task 4 wires callers.
function PetTrainer:ListFilter_Sync()
  if not installed then return end
  C_Timer.After(0, function()
    if not filterActive() then
      hideEmptyMessage()
      return
    end
    local todos = PetTrainer:GetTodoCraftIndices()
    if #todos == 0 then return end
    local sel = GetCraftSelectionIndex()
    for _, t in ipairs(todos) do
      if t.craftIndex == sel then return end
    end
    CraftFrame_SetSelection(todos[1].craftIndex)
    CraftFrame_Update()
  end)
end

-- Force a full repaint + selection sync. Used on preset change and when the
-- panel toggle flips (also restores the full list when the filter turns off).
function PetTrainer:ListFilter_Refilter()
  if not installed then return end
  if not CraftFrame or not CraftFrame:IsShown() or not isPetTraining() then return end
  if not filterActive() then hideEmptyMessage() end
  CraftFrame_Update()
  self:ListFilter_Sync()
end

-- Lazy install: Blizzard_CraftUI is load-on-demand, so none of the globals
-- exist until the first craft window opens.
function PetTrainer:ListFilter_OnCraftShow()
  if installed or standDown then
    if installed then self:ListFilter_Sync() end
    return
  end
  if checked then return end
  checked = true
  if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("MalfUI_BeastTrainingFilter") then
    standDown = true
    self:Print("Beast Training list filter disabled: MalfUI_BeastTrainingFilter is handling the list.")
    return
  end
  for i = 1, #REQUIRED do
    if _G[REQUIRED[i]] == nil then
      standDown = true
      self:Print("Beast Training list filter disabled: client UI global '" .. REQUIRED[i] .. "' is missing.")
      return
    end
  end
  hooksecurefunc("CraftFrame_Update", function()
    if filterActive() then renderFilteredList() end
  end)
  installed = true
  self:ListFilter_Sync()
end
