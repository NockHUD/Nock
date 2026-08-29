-- UI/Frame_Mailbox.lua
-- Snowball panel glued under the default MailFrame: report line, recipient
-- selector (click to cycle), and the Send / Return All / Stop actions.
-- Strictly a consumer of the Mailbox module API — no mail API calls here.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local MailboxView = Nock:NewModule("MailboxView", "AceEvent-3.0")
local C = Nock.Constants

local PAD     = 8
local BTN_H   = 21
local BTN_GAP = 5
local LINE_H  = 14
-- mails/To: row + snowballs/expiry row + action row
local HEIGHT  = PAD + BTN_H + 3 + LINE_H + 6 + BTN_H + PAD

local WARN_COLOR = "|cffff5555"
local OK_COLOR   = "|cffffffff"

local function isEnabled()
  local p = Nock.db and Nock.db.profile
  return (p and p.mailboxEnabled) ~= false
end

local function engine()
  return Nock:GetModule("Mailbox", true)
end

local function setEnabled(btn, on)
  if on then btn:Enable() else btn:Disable() end
end

local function snowballsInBags()
  if C_Item and C_Item.GetItemCount then
    return C_Item.GetItemCount(C.SNOWBALL_ITEM) or 0
  elseif GetItemCount then
    return GetItemCount(C.SNOWBALL_ITEM) or 0
  end
  return 0
end

function MailboxView:OnInitialize()
  if not MailFrame then return end

  local panel = CreateFrame("Frame", "NockMailbox", MailFrame, "BackdropTemplate")
  -- The classic frame's Inbox/Send Mail tabs hang below the frame's bottom
  -- edge — sit beneath them, not on them.
  local tabDrop = (MailFrameTab1 and MailFrameTab1:GetHeight() or 30) + 2
  panel:SetPoint("TOPLEFT", MailFrame, "BOTTOMLEFT", 2, -tabDrop)
  panel:SetPoint("TOPRIGHT", MailFrame, "BOTTOMRIGHT", -2, -tabDrop)
  panel:SetHeight(HEIGHT)
  Nock.UI.ApplyBackdrop(panel)
  panel:SetBackdropColor(0, 0, 0, 0.78)
  panel:Hide()

  -- Top row: report text on the left, the To: selector on the right.
  -- Bottom row: the three action buttons, splitting the width evenly (their
  -- widths are set in Refresh from the panel's real size, so the layout can
  -- never overflow the frame).
  local toBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  toBtn:SetSize(120, BTN_H)
  toBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, -PAD)
  toBtn:SetScript("OnClick", function()
    local m = engine()
    if m then m:CycleSessionRecipient() end
  end)
  toBtn:SetScript("OnEnter", function(btn)
    GameTooltip:SetOwner(btn, "ANCHOR_TOP")
    GameTooltip:SetText("Send target — click to cycle through the recipient list (Options → Mailbox).")
    GameTooltip:Show()
  end)
  toBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  panel.toBtn = toBtn

  -- Info block: mail count top-left (beside the To: button), snowball count
  -- bottom-left, expiry bottom-right.
  local mailsText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  mailsText:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -PAD)
  mailsText:SetPoint("RIGHT", toBtn, "LEFT", -6, 0)
  mailsText:SetHeight(BTN_H)
  mailsText:SetJustifyH("LEFT")
  mailsText:SetJustifyV("MIDDLE")
  mailsText:SetWordWrap(false)
  panel.mailsText = mailsText

  local infoY = -(PAD + BTN_H + 3)
  local snowText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  snowText:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, infoY)
  snowText:SetPoint("TOPRIGHT", panel, "TOP", 0, infoY)
  snowText:SetHeight(LINE_H)
  snowText:SetJustifyH("LEFT")
  snowText:SetWordWrap(false)
  panel.snowText = snowText

  local expireText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  expireText:SetPoint("TOPLEFT", panel, "TOP", 0, infoY)
  expireText:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, infoY)
  expireText:SetHeight(LINE_H)
  expireText:SetJustifyH("RIGHT")
  expireText:SetWordWrap(false)
  panel.expireText = expireText

  local sendBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  sendBtn:SetSize(80, BTN_H)
  sendBtn:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", PAD, PAD)
  sendBtn:SetScript("OnClick", function()
    local m = engine()
    if not m then return end
    if m:IsBusy() then m:Stop() else m:StartSend() end
  end)
  sendBtn:SetScript("OnEnter", function(btn)
    GameTooltip:SetOwner(btn, "ANCHOR_TOP")
    GameTooltip:SetText("Loot every snowball mail into your bags and ship everything to the target. Click again to stop.")
    GameTooltip:Show()
  end)
  sendBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  sendBtn:SetText("Send All")
  panel.sendBtn = sendBtn

  local bagsBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  bagsBtn:SetSize(80, BTN_H)
  bagsBtn:SetPoint("BOTTOM", panel, "BOTTOM", 0, PAD)
  bagsBtn:SetText("Bags Only")
  bagsBtn:SetScript("OnClick", function()
    local m = engine()
    if m then m:StartSend(nil, true) end
  end)
  bagsBtn:SetScript("OnEnter", function(btn)
    GameTooltip:SetOwner(btn, "ANCHOR_TOP")
    GameTooltip:SetText("Ship only the snowballs already in your bags — the inbox mail is left alone.")
    GameTooltip:Show()
  end)
  bagsBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  panel.bagsBtn = bagsBtn

  local returnBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  returnBtn:SetSize(80, BTN_H)
  returnBtn:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -PAD, PAD)
  returnBtn:SetText("Return All")
  returnBtn:SetScript("OnClick", function()
    local m = engine()
    if m then m:StartReturn() end
  end)
  returnBtn:SetScript("OnEnter", function(btn)
    GameTooltip:SetOwner(btn, "ANCHOR_TOP")
    GameTooltip:SetText("Bounce every returnable snowball mail back to its sender (no bag space or postage needed). Mail that was already returned to you once can't be bounced again — loot & re-send it instead. COD mail is never touched.", nil, nil, nil, nil, true)
    GameTooltip:Show()
  end)
  returnBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  panel.returnBtn = returnBtn

  self.panel = panel
end

function MailboxView:OnEnable()
  self:RegisterMessage("NOCK_MAILBOX_CHANGED", "Refresh")
end

function MailboxView:Refresh()
  local panel = self.panel
  if not panel then return end
  local m = engine()
  if not m or not isEnabled() or not m.mailOpen then
    if panel:IsShown() then panel:Hide() end
    return
  end

  -- Size the action row off the panel's real width so it always fits.
  local w = panel:GetWidth() or 0
  if w > 0 then
    local btnW = math.floor((w - 2 * PAD - 2 * BTN_GAP) / 3)
    panel.sendBtn:SetWidth(btnW)
    panel.bagsBtn:SetWidth(btnW)
    panel.returnBtn:SetWidth(btnW)
  end

  local r = m:GetReport()
  local busy = m:IsBusy()
  local working = busy and "  |cffffcc00working…|r" or ""
  local bags = snowballsInBags()
  if r and r.mails > 0 then
    local dead = (r.deleteOnly or 0) > 0 and (" |cffaaaaaa(%d bounce-dead)|r"):format(r.deleteOnly) or ""
    panel.mailsText:SetText(("|cffffffff%d|r snowball mail(s)%s%s"):format(r.mails, dead, working))
    panel.snowText:SetText(("|cffffffff%d|r snowballs%s"):format(
      r.snowballs, bags > 0 and (" |cffaaaaaa(+%d in bags)|r"):format(bags) or ""))
    local dayCol = (r.minDays and r.minDays < C.MAIL_EXPIRY_WARN_DAYS) and WARN_COLOR or OK_COLOR
    panel.expireText:SetText(("expires in %s%.1f day(s)|r"):format(dayCol, r.minDays or 0))
  else
    panel.mailsText:SetText("No snowball mail" .. working)
    panel.snowText:SetText(bags > 0 and ("|cffffffff%d|r snowballs in bags"):format(bags) or "")
    panel.expireText:SetText("")
  end

  local recipient = m:GetSessionRecipient()
  panel.toBtn:SetText(("To: %s"):format(recipient or "—"))
  setEnabled(panel.toBtn, not busy)

  -- Buttons stay clickable even when there's nothing to do: the module
  -- prints WHY instead of the click silently doing nothing.
  panel.sendBtn:SetText(busy and "Stop" or "Send All")
  setEnabled(panel.sendBtn, true)
  setEnabled(panel.bagsBtn, not busy)
  setEnabled(panel.returnBtn, not busy)

  if not panel:IsShown() then panel:Show() end
end
