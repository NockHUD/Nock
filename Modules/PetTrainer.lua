-- Modules/PetTrainer.lua
-- Pet-training helper. Beast Training is a Craft frame we can READ but only
-- partly drive: DoCraft is taint-blocked from addon code, but selecting a craft
-- via CraftFrame_SetSelection (what Blizzard's own list rows call) DOES work from
-- a hardware-event click and syncs the detail panel + the selectedCraft the Train
-- button reads. So this shows a live per-raid checklist beside the window: click a
-- yellow to-do row to select it, then press the game's Train button. Done/todo and
-- TP totals refresh as you train.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local PetTrainer = Nock:NewModule("PetTrainer", "AceEvent-3.0", "AceConsole-3.0")

-- Shared DPS core for every raid; per-raid tables override Natural Armor / add
-- Great Stamina + resistances. Ability names must match the localized craft
-- names. Sourced from the user's Wowhead pet-training builds.
local function build(over)
  local b = {
    ["Growl"] = 8, ["Bite"] = 9, ["Gore"] = 9, ["Dash"] = 3,
    ["Cobra Reflexes"] = 1, ["Avoidance"] = 2, ["Natural Armor"] = 1,
  }
  for k, v in pairs(over) do b[k] = v end
  return b
end

local PRESETS = {
  tk   = { label = "TK",      build = build({ ["Arcane Resistance"] = 5, ["Fire Resistance"] = 5, ["Frost Resistance"] = 2 }) },
  ssc  = { label = "SSC",     build = build({ ["Natural Armor"] = 2, ["Great Stamina"] = 5,
                                              ["Fire Resistance"] = 1, ["Frost Resistance"] = 2,
                                              ["Nature Resistance"] = 5, ["Shadow Resistance"] = 3 }) },
  bt   = { label = "BT",      build = build({ ["Fire Resistance"] = 5, ["Frost Resistance"] = 2, ["Shadow Resistance"] = 5 }) },
  hy   = { label = "Hyjal",   build = build({ ["Fire Resistance"] = 5, ["Nature Resistance"] = 5, ["Shadow Resistance"] = 2 }) },
  sw   = { label = "Sunwell", build = build({ ["Arcane Resistance"] = 5, ["Fire Resistance"] = 2, ["Shadow Resistance"] = 5 }) },
}
local PRESET_ORDER = { "tk", "ssc", "bt", "hy", "sw" }
PetTrainer.PRESETS = PRESETS

local COL_DONE = { 0.45, 0.80, 0.45 }
local COL_TODO = { 1.00, 0.85, 0.25 }
local COL_OVER = { 0.95, 0.55, 0.20 }
local COL_MISS = { 0.55, 0.55, 0.55 }
local STATUS_ORDER = { todo = 1, over = 2, missing = 3, done = 4 }
local ROW_H = 16
local ROW_TOP = 68  -- y offset of the first checklist row (below selector row + title + summary)

local function rankOf(sub)
  if type(sub) ~= "string" then return 1 end
  local n = sub:match("(%d+)")
  return n and tonumber(n) or 1
end

local function unspentTP()
  if not GetPetTrainingPoints then return nil end
  local t, s = GetPetTrainingPoints()
  if type(t) ~= "number" or type(s) ~= "number" then return nil end
  return t - s
end

-- Pure analysis core (standalone-testable; see Tests/pettrainer_analyze_test.lua).
-- crafts: array where index == craft index, entries {name, sub, ctype, tp}.
-- build: map abilityName -> targetRank. Returns one item per build ability:
-- {name, target, current, status, selIdx, selRank, selTP, iconIdx} where selIdx
-- is the craft index of the highest not-yet-trained rank <= target.
function PetTrainer.AnalyzeBuild(crafts, build)
  local items = {}
  for name, target in pairs(build) do
    local current, selIdx, selRank, selTP, seen, iconIdx = 0, nil, nil, nil, false, nil
    for i = 1, #crafts do
      local c = crafts[i]
      if c.name == name then
        seen = true
        iconIdx = iconIdx or i
        local r = rankOf(c.sub)
        if c.ctype == "used" then
          if r > current then current = r end
        elseif r <= target and (not selRank or r > selRank) then
          selRank, selIdx, selTP = r, i, c.tp
        end
      end
    end
    local status
    if not seen then status = "missing"
    elseif current > target then status = "over"
    elseif current == target then status = "done"
    else status = "todo" end
    items[#items + 1] = {
      name = name, target = target, current = current, status = status,
      selIdx = selIdx, selRank = selRank, selTP = selTP, iconIdx = iconIdx,
    }
  end
  return items
end

-- Snapshot the open craft list into a reusable scratch table (rebuilt on every
-- call; only runs while the trainer window is open, so allocation is bounded).
local craftScratch = {}
local function snapshotCrafts()
  local nc = (GetNumCrafts and GetNumCrafts()) or 0
  for i = 1, nc do
    local row = craftScratch[i]
    if not row then row = {}; craftScratch[i] = row end
    local cname, sub, ctype, _, _, tp = GetCraftInfo(i)
    row.name, row.sub, row.ctype, row.tp = cname, sub, ctype, tp
  end
  local n = #craftScratch
  for i = nc + 1, n do craftScratch[i] = nil end
  return craftScratch
end

-- Items for the active preset against the open craft list, or nil.
function PetTrainer:GetItems()
  local preset = PRESETS[self.active]
  if not preset then return nil end
  return PetTrainer.AnalyzeBuild(snapshotCrafts(), preset.build)
end

-- Remaining to-dos in Blizzard-list order, plus the count of over-target
-- abilities (training can't fix those; the list filter reports them).
function PetTrainer:GetTodoCraftIndices()
  local todos, over = {}, 0
  local items = self:GetItems()
  if items then
    for _, it in ipairs(items) do
      if it.status == "todo" and it.selIdx then
        todos[#todos + 1] = { craftIndex = it.selIdx, name = it.name, rank = it.selRank, tp = it.selTP }
      elseif it.status == "over" then
        over = over + 1
      end
    end
    table.sort(todos, function(a, b) return a.craftIndex < b.craftIndex end)
  end
  return todos, over
end

local function profileGet(key, fallback)
  local p = Nock.db and Nock.db.profile
  if p and p[key] ~= nil then return p[key] end
  return fallback
end

function PetTrainer:OnInitialize()
  local saved = profileGet("petTrainerPreset", "ssc")
  self.active = PRESETS[saved] and saved or "ssc"
end

function PetTrainer:OnEnable()
  self:RegisterEvent("CRAFT_SHOW", "OnCraftShow")
  self:RegisterEvent("CRAFT_UPDATE", "Refresh")
  self:RegisterEvent("CRAFT_CLOSE", "OnCraftClose")
end

function PetTrainer:EnsurePanel()
  if self.panel then return self.panel end
  local f = CreateFrame("Frame", "NockPetTrainerPanel", UIParent, "BackdropTemplate")
  f:SetSize(300, 220)
  Nock.UI.ApplyBackdrop(f)
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)

  -- Raid selector: one row of buttons.
  f.selBtns = {}
  for idx, key in ipairs(PRESET_ORDER) do
    local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    b:SetSize(56, 18)
    b:SetPoint("TOPLEFT", 8 + (idx - 1) * 58, -8)
    b:SetText(PRESETS[key].label)
    if b.GetFontString and b:GetFontString() then
      b:GetFontString():SetFont(Nock.UI.GetFont(), 10, "OUTLINE")
    end
    b:SetScript("OnClick", function() PetTrainer:SetActive(key) end)
    f.selBtns[key] = b
  end

  local title = f:CreateFontString(nil, "OVERLAY")
  title:SetFont(Nock.UI.GetFont(), 12, "OUTLINE")
  title:SetPoint("TOPLEFT", 10, -32)
  f.title = title

  local sub = f:CreateFontString(nil, "OVERLAY")
  sub:SetFont(Nock.UI.GetFont(), 10, "OUTLINE")
  sub:SetPoint("TOPLEFT", 10, -50)
  sub:SetTextColor(0.8, 0.8, 0.8)
  f.sub = sub

  -- Blizzard-list filter toggle (bottom-left; Refresh reserves the height).
  local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
  cb:SetSize(20, 20)
  cb:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 8, 4)
  local cbLabel = f:CreateFontString(nil, "OVERLAY")
  cbLabel:SetFont(Nock.UI.GetFont(), 10, "OUTLINE")
  cbLabel:SetPoint("LEFT", cb, "RIGHT", 2, 0)
  cbLabel:SetText("Filter trainer list")
  cbLabel:SetTextColor(0.8, 0.8, 0.8)
  cb:SetScript("OnClick", function(btn)
    if Nock.db and Nock.db.profile then
      Nock.db.profile.petTrainerListFilter = (btn:GetChecked() and true) or false
    end
    if PetTrainer.ListFilter_Refilter then PetTrainer:ListFilter_Refilter() end
  end)
  f.filterToggle = cb

  f.rows = {}
  self.panel = f
  return f
end

function PetTrainer:GetRow(i)
  local f = self.panel
  local r = f.rows[i]
  if not r then
    r = CreateFrame("Button", nil, f)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -ROW_TOP - (i - 1) * ROW_H)
    r:SetPoint("RIGHT", f, "RIGHT", -10, 0)
    local ico = r:CreateTexture(nil, "ARTWORK")
    ico:SetSize(13, 13)
    ico:SetPoint("LEFT", 0, 0)
    ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.icon = ico
    local t = r:CreateFontString(nil, "OVERLAY")
    t:SetFont(Nock.UI.GetFont(), 11, "OUTLINE")
    t:SetPoint("LEFT", ico, "RIGHT", 4, 0)
    t:SetJustifyH("LEFT")
    r.text = t
    r:SetScript("OnClick", function()
      if r._selIdx then PetTrainer:OnRowClick(r._selIdx, r._name, r._selRank) end
    end)
    r:SetScript("OnEnter", function() r:SetAlpha(0.6) end)
    r:SetScript("OnLeave", function() r:SetAlpha(1) end)
    f.rows[i] = r
  end
  return r
end

-- Select the craft so the user only has to press the game's Train button. Use
-- CraftFrame_SetSelection (Blizzard's own row handler) so the detail panel and the
-- selectedCraft the Train button reads both sync. Runs from a real button click.
function PetTrainer:OnRowClick(idx, name, rank)
  if CraftFrame_SetSelection then
    CraftFrame_SetSelection(idx)
    if CraftFrame_Update then CraftFrame_Update() end
  elseif SelectCraft then
    SelectCraft(idx)
  end
  self:Print(("Selected %s (rank %s) -- press the game's Train button."):format(tostring(name), tostring(rank)))
end

function PetTrainer:SetActive(key)
  if not PRESETS[key] then return end
  self.active = key
  if Nock.db and Nock.db.profile then Nock.db.profile.petTrainerPreset = key end
  self:Refresh()
  if self.ListFilter_Refilter then self:ListFilter_Refilter() end
end

function PetTrainer:UpdateSelector()
  if not self.panel or not self.panel.selBtns then return end
  for key, b in pairs(self.panel.selBtns) do
    if key == self.active then b:LockHighlight() else b:UnlockHighlight() end
  end
end

function PetTrainer:OnCraftShow()
  if self.ListFilter_OnCraftShow then self:ListFilter_OnCraftShow() end
  if profileGet("petTrainerHelperEnabled", true) == false then return end
  local f = self:EnsurePanel()
  f:ClearAllPoints()
  local anchor = _G.CraftFrame
  if anchor then
    f:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 6, 0)
  else
    f:SetPoint("CENTER", UIParent, "CENTER", 300, 0)
  end
  f:Show()
  self:Refresh()
end

function PetTrainer:OnCraftClose()
  if self.panel then self.panel:Hide() end
end

function PetTrainer:Refresh()
  if not self.panel or not self.panel:IsShown() then return end
  local preset = PRESETS[self.active]
  if not preset then return end
  local f = self.panel
  self:UpdateSelector()
  if f.filterToggle then
    f.filterToggle:SetChecked(profileGet("petTrainerListFilter", true) ~= false)
  end
  f.title:SetText("Nock \226\128\148 Pet Training: " .. preset.label)

  if next(preset.build) == nil then
    f.sub:SetText("No template for this raid yet.")
    for j = 1, #f.rows do f.rows[j]:Hide() end
    f:SetHeight(ROW_TOP + 8 + 24)
    return
  end

  local items = self:GetItems()
  if not items then return end
  for _, it in ipairs(items) do
    it.icon = (it.iconIdx and GetCraftIcon) and GetCraftIcon(it.iconIdx) or nil
  end
  table.sort(items, function(a, b)
    local oa, ob = STATUS_ORDER[a.status] or 9, STATUS_ORDER[b.status] or 9
    if oa ~= ob then return oa < ob end
    return a.name < b.name
  end)

  local todo, tpNeeded = 0, 0
  for _, it in ipairs(items) do
    if it.status == "todo" and it.selTP then todo = todo + 1; tpNeeded = tpNeeded + it.selTP end
  end
  f.sub:SetText(("%d to train  -  %s TP needed  -  %s unspent"):format(todo, tostring(tpNeeded), tostring(unspentTP())))

  local i = 0
  for _, it in ipairs(items) do
    i = i + 1
    local r = self:GetRow(i)
    r._selIdx, r._name, r._selRank = nil, nil, nil
    r.icon:SetTexture(it.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    r.icon:SetDesaturated(it.status == "done" or it.status == "missing")
    local label, col
    if it.status == "done" then
      label, col = ("[x] %s %d"):format(it.name, it.target), COL_DONE
    elseif it.status == "todo" then
      label, col = ("%s -> rank %d  (%s TP)"):format(it.name, it.target, tostring(it.selTP or "-")), COL_TODO
      r._selIdx, r._name, r._selRank = it.selIdx, it.name, it.selRank
    elseif it.status == "over" then
      label, col = ("[!] %s  %d->%d (untrain)"):format(it.name, it.current, it.target), COL_OVER
    else
      label, col = ("%s (not available)"):format(it.name), COL_MISS
    end
    r.text:SetText(label)
    r.text:SetTextColor(col[1], col[2], col[3])
    r:Show()
  end
  for j = i + 1, #f.rows do f.rows[j]:Hide() end
  f:SetHeight(ROW_TOP + i * ROW_H + 8 + 24)
  if self.ListFilter_Sync then self:ListFilter_Sync() end
end

-- /nock pettrain [preset|list] — also selectable via the panel's raid buttons.
function PetTrainer:Command(args)
  local key = (args or ""):lower():gsub("%s+", "")
  if key == "" or key == "list" then
    local names = {}
    for _, k in ipairs(PRESET_ORDER) do names[#names + 1] = k end
    self:Print("pettrain presets: " .. table.concat(names, ", ")
      .. " -- usage: /nock pettrain <preset>, or use the raid buttons on the panel")
    return
  end
  if not PRESETS[key] then self:Print("pettrain: unknown preset '" .. key .. "'"); return end
  self:SetActive(key)
  self:Print("pettrain: active preset = " .. PRESETS[key].label)
end
