-- Modules/Mailbox.lua
-- Snowball mail logistics: inbox report, mass return-to-sender, and an
-- auto-loot + auto-send run that ships snowballs to another of your chars.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local Mailbox = Nock:NewModule("Mailbox", "AceEvent-3.0", "AceTimer-3.0", "AceConsole-3.0")
local C = Nock.Constants

local POLL          = 0.1   -- pending-state poll cadence during runs
local SCAN_DEBOUNCE = 0.2   -- MAIL_INBOX_UPDATE coalescing
local BAG_GRACE     = 2     -- max wait for BAG_UPDATE after a send resolves

local ATTACH_RECV_MAX = _G.ATTACHMENTS_MAX_RECEIVE or 16

local function isEnabled()
  local p = Nock.db and Nock.db.profile
  return (p and p.mailboxEnabled) ~= false
end

local function attachSendMax()
  return _G.ATTACHMENTS_MAX_SEND or C.MAIL_ATTACH_MAX
end

-- One mail command in flight at a time; the server ignores overlap.
local function commandPending()
  return (C_Mail and C_Mail.IsCommandPending and C_Mail.IsCommandPending()) or false
end

-- Dual-form container APIs (the modernized client namespaces these under
-- C_Container; keep the bare-global fallback per house style).
local function containerNumSlots(bag)
  if C_Container and C_Container.GetContainerNumSlots then
    return C_Container.GetContainerNumSlots(bag)
  elseif GetContainerNumSlots then
    return GetContainerNumSlots(bag)
  end
  return 0
end

local function containerFreeSlots(bag)
  if C_Container and C_Container.GetContainerNumFreeSlots then
    return C_Container.GetContainerNumFreeSlots(bag)
  elseif GetContainerNumFreeSlots then
    return GetContainerNumFreeSlots(bag)
  end
  return 0, 0
end

local function containerItemID(bag, slot)
  if C_Container and C_Container.GetContainerItemID then
    return C_Container.GetContainerItemID(bag, slot)
  elseif GetContainerItemID then
    return GetContainerItemID(bag, slot)
  end
end

local function containerSlotInfo(bag, slot)  -- -> count, locked (nil = empty)
  if C_Container and C_Container.GetContainerItemInfo then
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if info then return info.stackCount or 1, info.isLocked or false end
    return nil
  elseif GetContainerItemInfo then
    local _, count, locked = GetContainerItemInfo(bag, slot)
    if count then return count, locked or false end
    return nil
  end
end

local function pickupContainerItem(bag, slot)
  if C_Container and C_Container.PickupContainerItem then
    C_Container.PickupContainerItem(bag, slot)
  elseif PickupContainerItem then
    PickupContainerItem(bag, slot)
  end
end

-- GetCursorInfo is the modern-client truth; bare CursorHasItem may be nil.
local function cursorHasItem()
  if GetCursorInfo then return (GetCursorInfo()) == "item" end
  if CursorHasItem then return CursorHasItem() end
  return false
end

-- Drive the default mail UI's tabs so the run is visible and attaching
-- happens in the state the Blizzard UI expects (Postal's forward feature
-- switches tabs the same way before attaching).
local function showMailTab(n)
  local frame = (n == 2) and SendMailFrame or InboxFrame
  if frame and frame:IsShown() then return end
  if MailFrameTab_OnClick then
    MailFrameTab_OnClick(nil, n)
  else
    local tab = _G["MailFrameTab" .. n]
    if tab and tab.Click then tab:Click() end
  end
end

-- Snowballs can't live in a quiver/pouch: only bagFamily 0 counts.
local function freeGeneralSlots()
  local total = 0
  for bag = 0, 4 do
    local free, family = containerFreeSlots(bag)
    if (family or 0) == 0 then total = total + (free or 0) end
  end
  return total
end

-- Fields off the classic 13-return GetInboxHeaderInfo signature.
local function mailHeader(i)
  local _, _, sender, _, _, cod, daysLeft, itemCount, _, wasReturned = GetInboxHeaderInfo(i)
  return sender, cod or 0, daysLeft or 0, tonumber(itemCount) or 0, wasReturned
end

-- Snowballs inside inbox mail i: total count + attachment slots used.
-- Identified by item ID parsed from the link; the count is the 4th return of
-- GetInboxItem on this client (TSM does the same).
local function mailSnowballs(i)
  local snow, attachments = 0, 0
  for j = 1, ATTACH_RECV_MAX do
    local link = GetInboxItemLink and GetInboxItemLink(i, j)
    if link then
      attachments = attachments + 1
      if tonumber(link:match("item:(%d+)")) == C.SNOWBALL_ITEM then
        local _, _, _, count = GetInboxItem(i, j)
        snow = snow + (count or 1)
      end
    end
  end
  return snow, attachments
end

-- ---------------------------------------------------------------------------
-- Lifecycle + inbox scan
-- ---------------------------------------------------------------------------

function Mailbox:OnEnable()
  self.report = self.report or {
    mails = 0, snowballs = 0, minDays = nil,
    returnable = 0, deleteOnly = 0, cod = 0, shown = 0, total = 0,
  }
  self.mailOpen = false
  self:RegisterEvent("MAIL_SHOW")
  self:RegisterEvent("MAIL_CLOSED")
end

function Mailbox:OnDisable()
  self:EndRun(nil)
  self.mailOpen = false
end

function Mailbox:MAIL_SHOW()
  if not isEnabled() then return end
  self.mailOpen = true
  self:RegisterEvent("MAIL_INBOX_UPDATE")
  self:QueueScan()
end

function Mailbox:MAIL_CLOSED()
  self.mailOpen = false
  self:UnregisterEvent("MAIL_INBOX_UPDATE")
  if self.run then self:EndRun("Mailbox: mailbox closed — run stopped.") end
  self:SendMessage("NOCK_MAILBOX_CHANGED")
end

function Mailbox:MAIL_INBOX_UPDATE()
  if self.run then
    self.run.inboxDirty = true  -- runs rescan themselves between ops
    return
  end
  self:QueueScan()
end

function Mailbox:QueueScan()
  if self._scanQueued then return end
  self._scanQueued = true
  self:ScheduleTimer(function()
    self._scanQueued = false
    if self.mailOpen then self:ScanInbox() end
  end, SCAN_DEBOUNCE)
end

function Mailbox:ScanInbox()
  local r = self.report
  if not r then return end
  local shown, total = GetInboxNumItems()
  r.mails, r.snowballs, r.returnable, r.deleteOnly, r.cod = 0, 0, 0, 0, 0
  r.minDays = nil
  r.shown = shown or 0
  r.total = total or shown or 0
  for i = 1, r.shown do
    local _, cod, daysLeft, itemCount = mailHeader(i)
    if itemCount > 0 then
      local snow = mailSnowballs(i)
      if snow > 0 then
        r.mails = r.mails + 1
        r.snowballs = r.snowballs + snow
        if not r.minDays or daysLeft < r.minDays then r.minDays = daysLeft end
        if cod > 0 then
          r.cod = r.cod + 1
        elseif InboxItemCanDelete and InboxItemCanDelete(i) then
          r.deleteOnly = r.deleteOnly + 1   -- bounced once: return is spent
        else
          r.returnable = r.returnable + 1
        end
      end
    end
  end
  self:SendMessage("NOCK_MAILBOX_CHANGED")
end

function Mailbox:GetReport()
  return self.report
end

-- ---------------------------------------------------------------------------
-- Recipients (account-wide list, per-character session prefill)
-- ---------------------------------------------------------------------------

function Mailbox:GetRecipients()
  local g = Nock.db and Nock.db.global
  return (g and g.mailboxRecipients) or {}
end

function Mailbox:GetSessionRecipient()
  local me = (UnitName("player") or ""):lower()
  local c = Nock.db and Nock.db.char
  local last = c and c.mailboxLastRecipient or ""
  if last ~= "" and last:lower() ~= me then
    for _, n in ipairs(self:GetRecipients()) do
      if n:lower() == last:lower() then return n end
    end
  end
  for _, n in ipairs(self:GetRecipients()) do
    if n:lower() ~= me then return n end
  end
  return nil
end

function Mailbox:SetSessionRecipient(name)
  if Nock.db and Nock.db.char then Nock.db.char.mailboxLastRecipient = name or "" end
  self:SendMessage("NOCK_MAILBOX_CHANGED")
end

function Mailbox:CycleSessionRecipient()
  local me = (UnitName("player") or ""):lower()
  local usable = {}
  for _, n in ipairs(self:GetRecipients()) do
    if n:lower() ~= me then usable[#usable + 1] = n end
  end
  if #usable == 0 then
    self:Print("No usable recipients — add character names under Options → Mailbox.")
    return nil
  end
  local cur, idx = self:GetSessionRecipient(), 1
  for k, n in ipairs(usable) do
    if cur and n:lower() == cur:lower() then
      idx = (k % #usable) + 1
      break
    end
  end
  self:SetSessionRecipient(usable[idx])
  return usable[idx]
end

function Mailbox:MatchRecipient(needle)
  needle = (needle or ""):lower()
  for _, n in ipairs(self:GetRecipients()) do
    if n:lower() == needle then return n end
  end
end

-- ---------------------------------------------------------------------------
-- Run engine: one op in flight, rescan between ops, poll-gated on the server
-- ---------------------------------------------------------------------------

function Mailbox:IsBusy()
  return self.run ~= nil
end

function Mailbox:Stop()
  if self.run then self:EndRun("Mailbox: run stopped.") end
end

function Mailbox:EndRun(msg)
  local hadRun = self.run ~= nil
  self.run = nil
  self._wait = nil
  if self._stepTimer then
    self:CancelTimer(self._stepTimer)
    self._stepTimer = nil
  end
  if not hadRun then return end
  if cursorHasItem() and ClearCursor then ClearCursor() end
  if ClearSendMail then ClearSendMail() end
  self:UnregisterEvent("MAIL_FAILED")
  self:UnregisterEvent("MAIL_SUCCESS")
  self:UnregisterEvent("BAG_UPDATE")
  if msg then self:Print(msg) end
  if self.mailOpen then self:QueueScan() end
  self:SendMessage("NOCK_MAILBOX_CHANGED")
end

-- Hold until no mail command is pending AND opts.check passes, then settle
-- and continue with nextMethod. Hard timeout aborts the run; opts.soft makes
-- the timeout proceed instead (post-send bag refresh).
function Mailbox:WaitThen(nextMethod, opts)
  self._wait = {
    nextMethod = nextMethod,
    check      = opts and opts.check,
    soft       = opts and opts.soft,
    deadline   = GetTime() + ((opts and opts.timeout) or C.MAIL_OP_TIMEOUT),
  }
  self:Pump()
end

function Mailbox:Pump()
  local w = self._wait
  if not w or not self.run then return end
  local blocked = commandPending() or (w.check and not w.check())
  if blocked and GetTime() <= w.deadline then
    self._stepTimer = self:ScheduleTimer("Pump", POLL)
    return
  end
  if blocked and not w.soft then
    self:EndRun("Mailbox: no server response — run stopped.")
    return
  end
  self._wait = nil
  self._stepTimer = self:ScheduleTimer(w.nextMethod, C.MAIL_STEP_SETTLE)
end

function Mailbox:OnRunMailFailed()
  local run = self.run
  if not run then return end
  if run.mode == "return" then
    self:EndRun("Mailbox: the server refused a return — stopped.")
  elseif run.phase == "awaitSend" then
    self:EndRun(("Mailbox: sending to '%s' failed (misspelled? cross-faction?) — stopped."):format(run.recipient))
  else
    run.phase = "send"  -- loot refused (usually bags): ship what we have
  end
end

function Mailbox:OnRunMailSuccess()
  local run = self.run
  if run and run.phase == "awaitSend" then run.sendConfirmed = true end
end

function Mailbox:OnRunBagUpdate()
  if self.run then self.run.bagDirty = true end
end

local function registerRunEvents(self)
  self:RegisterEvent("MAIL_FAILED", "OnRunMailFailed")
  self:RegisterEvent("MAIL_SUCCESS", "OnRunMailSuccess")
  self:RegisterEvent("BAG_UPDATE", "OnRunBagUpdate")
end

-- Runaway guard shared by both run types: a legitimate run is at most a few
-- ops per mail; anything past this is a loop that isn't making progress.
local function countOp(self)
  local run = self.run
  run.ops = (run.ops or 0) + 1
  if run.ops > 300 then
    self:EndRun("Mailbox: too many steps without finishing — stopped.")
    return false
  end
  return true
end

-- ---------------------------------------------------------------------------
-- Mass return-to-sender
-- ---------------------------------------------------------------------------

-- Highest-index snowball mail that can still be bounced to its sender.
function Mailbox:FindReturnTarget()
  for i = (GetInboxNumItems() or 0), 1, -1 do
    local _, cod, _, itemCount = mailHeader(i)
    if itemCount > 0 and cod == 0
      and not (InboxItemCanDelete and InboxItemCanDelete(i)) then
      if mailSnowballs(i) > 0 then return i end
    end
  end
end

function Mailbox:StartReturn()
  if self.run then self:Stop() return end
  if not isEnabled() then self:Print("Mailbox helper is disabled (Options → Mailbox).") return end
  if not self.mailOpen then self:Print("Open a mailbox first.") return end
  self.run = { mode = "return", returned = 0 }
  registerRunEvents(self)
  self:SendMessage("NOCK_MAILBOX_CHANGED")
  self:ReturnStep()
end

function Mailbox:ReturnStep()
  local run = self.run
  if not run or run.mode ~= "return" then return end
  if not countOp(self) then return end
  local i = self:FindReturnTarget()
  if not i then
    self:ScanInbox()
    local r = self.report
    local msg = ("Mailbox: returned %d snowball mail(s) to sender."):format(run.returned)
    if r.deleteOnly > 0 then
      msg = msg .. (" %d bounced mail(s) can't be returned again — loot & re-send those with Send."):format(r.deleteOnly)
    end
    if r.cod > 0 then
      msg = msg .. (" %d COD mail(s) left untouched."):format(r.cod)
    end
    if r.total > r.shown then
      msg = msg .. (" %d more mail(s) are queued beyond the visible inbox — run again in ~1 minute."):format(r.total - r.shown)
    end
    self:EndRun(msg)
    return
  end
  run.inboxDirty = false
  local preShown = GetInboxNumItems() or 0
  ReturnInboxItem(i)
  run.returned = run.returned + 1
  -- Wait for the inbox to actually change (event flag OR the mail count
  -- moving — this client doesn't reliably fire MAIL_INBOX_UPDATE after a
  -- return) so the rescan never sees the outgoing mail still cached. Short
  -- soft timeout: the rescan self-corrects either way.
  self:WaitThen("ReturnStep", {
    check = function()
      return run.inboxDirty or (GetInboxNumItems() or 0) ~= preShown
    end,
    timeout = 2, soft = true,
  })
end

-- ---------------------------------------------------------------------------
-- Auto-loot + auto-send run
-- ---------------------------------------------------------------------------

-- Highest-index lootable snowball mail (COD skipped) + its attachment count.
function Mailbox:FindLootTarget()
  for i = (GetInboxNumItems() or 0), 1, -1 do
    local _, cod, _, itemCount = mailHeader(i)
    if itemCount > 0 and cod == 0 then
      local snow, attachments = mailSnowballs(i)
      if snow > 0 then return i, attachments end
    end
  end
end

-- Snowball stacks in the general bags minus the configured keep amount
-- (whole stacks — the keep rounds UP). Locked slots are skipped: a stack
-- attached to an in-flight mail stays locked until the send resolves.
function Mailbox:CollectSendableStacks()
  local p = Nock.db and Nock.db.profile
  local keepLeft = (p and p.mailboxKeepCount) or 0
  local out = {}
  for bag = 0, 4 do
    local _, family = containerFreeSlots(bag)
    if (family or 0) == 0 then
      for slot = 1, containerNumSlots(bag) or 0 do
        if containerItemID(bag, slot) == C.SNOWBALL_ITEM then
          local count, locked = containerSlotInfo(bag, slot)
          if count and not locked then
            if keepLeft > 0 then
              keepLeft = keepLeft - count
            else
              out[#out + 1] = { bag = bag, slot = slot, count = count }
            end
          end
        end
      end
    end
  end
  return out
end

function Mailbox:StartSend(recipient, bagsOnly)
  if self.run then self:Stop() return end
  if not isEnabled() then self:Print("Mailbox helper is disabled (Options → Mailbox).") return end
  if not self.mailOpen then self:Print("Open a mailbox first.") return end
  recipient = recipient or self:GetSessionRecipient()
  if not recipient or recipient == "" then
    self:Print("Mailbox: no send recipient — add character names under Options → Mailbox.")
    return
  end
  local me = UnitName("player")
  if me and recipient:lower() == me:lower() then
    self:Print("Mailbox: can't mail snowballs to yourself — pick another recipient.")
    return
  end
  self:SetSessionRecipient(recipient)
  self.run = {
    mode = "send", phase = bagsOnly and "send" or "loot",
    bagsOnly = bagsOnly or nil, recipient = recipient,
    sent = 0, looted = 0, snowballsSent = 0,
  }
  registerRunEvents(self)
  self:Print(("Mailbox: shipping %s to %s (the send-mail draft is used — any half-written mail is cleared)."):format(
    bagsOnly and "bag snowballs only" or "snowballs", recipient))
  self:SendMessage("NOCK_MAILBOX_CHANGED")
  self:SendStep()
end

function Mailbox:SendStep()
  local run = self.run
  if not run or run.mode ~= "send" then return end
  if not countOp(self) then return end

  if run.phase == "loot" then
    local i, attachments = self:FindLootTarget()
    if i and freeGeneralSlots() >= (attachments or 1) then
      showMailTab(1)
      run.looted = run.looted + 1
      if AutoLootMailItem then
        AutoLootMailItem(i)
      elseif TakeInboxItem then
        -- Per-attachment fallback (Postal's approach): take the first one;
        -- the rescan loop comes back for the rest and the server deletes the
        -- mail once it's empty.
        for j = 1, ATTACH_RECV_MAX do
          if GetInboxItemLink(i, j) then
            TakeInboxItem(i, j)
            break
          end
        end
      else
        self:EndRun("Mailbox: no mail-loot API on this client — stopped.")
        return
      end
      -- Loot changes the bags (and usually the inbox); wait for either
      -- signal with a short soft timeout — the rescan self-corrects.
      run.bagDirty = false
      run.inboxDirty = false
      self:WaitThen("SendStep", {
        check = function() return run.bagDirty or run.inboxDirty end,
        timeout = BAG_GRACE, soft = true,
      })
      return
    end
    run.phase = "send"  -- nothing lootable (or no bag room): ship the bags
  end

  if run.phase == "send" then
    local slots = self:CollectSendableStacks()
    if #slots == 0 then
      local i, attachments = self:FindLootTarget()
      if not run.bagsOnly and i and freeGeneralSlots() >= (attachments or 1) then
        run.phase = "loot"
        self:SendStep()
      else
        self:FinishSendRun(i ~= nil)
      end
      return
    end
    -- Attach with the Send Mail tab up, the state the default UI expects —
    -- and it makes the run visible: recipient/subject filled in, slots
    -- populating, mail going out.
    showMailTab(2)
    ClearSendMail()
    if SendMailNameEditBox then SendMailNameEditBox:SetText(run.recipient) end
    if SendMailSubjectEditBox then SendMailSubjectEditBox:SetText("Snowballs") end
    -- Attach optimistically: clicking with an empty cursor is a no-op, and
    -- the pending-attachment count below is the real verification.
    local batch = 0
    for k = 1, math.min(#slots, attachSendMax()) do
      local s = slots[k]
      pickupContainerItem(s.bag, s.slot)
      ClickSendMailItemButton()
      if cursorHasItem() then
        if ClearCursor then ClearCursor() end
        self:EndRun("Mailbox: couldn't attach a snowball stack — stopped.")
        return
      end
      batch = batch + s.count
    end
    local pending = 0
    for n = 1, attachSendMax() do
      if GetSendMailItem and GetSendMailItem(n) then pending = pending + 1 end
    end
    if pending == 0 then
      self:EndRun("Mailbox: attaching snowballs failed (nothing landed in the attachment slots) — stopped.")
      return
    end
    run.phase = "awaitSend"
    run.sendConfirmed = false
    run.bagDirty = false
    run.batch = batch
    SendMail(run.recipient, "Snowballs", "")
    self:WaitThen("AfterSend", { check = function() return run.sendConfirmed end })
  end
end

function Mailbox:AfterSend()
  local run = self.run
  if not run then return end
  run.sent = run.sent + 1
  run.snowballsSent = run.snowballsSent + (run.batch or 0)
  run.phase = "postSend"
  -- Attached stacks sit locked in the bags until the send resolves; wait for
  -- a bag update (or a short grace) before walking the bags again.
  self:WaitThen("ResumeAfterSend", {
    check = function() return run.bagDirty end,
    timeout = BAG_GRACE, soft = true,
  })
end

function Mailbox:ResumeAfterSend()
  local run = self.run
  if not run then return end
  -- Prefer refilling the bags before the next send (unless bags-only).
  run.phase = run.bagsOnly and "send" or "loot"
  self:SendStep()
end

function Mailbox:FinishSendRun(mailLeft)
  local run = self.run
  if not run then return end
  self:ScanInbox()
  local r = self.report
  local msg = ("Mailbox: sent %d mail(s), ~%d snowballs, to %s (looted %d mail(s))."):format(
    run.sent, run.snowballsSent, run.recipient, run.looted)
  if mailLeft then
    if run.bagsOnly then
      msg = msg .. " Snowball mail is still in the inbox — use Send to loot & ship it too."
    else
      msg = msg .. " Some snowball mail couldn't be looted — free up bag space and run Send again."
    end
  end
  if r.total > r.shown then
    msg = msg .. (" %d more mail(s) are queued beyond the visible inbox — run again in ~1 minute."):format(r.total - r.shown)
  end
  if r.cod > 0 then
    msg = msg .. (" %d COD mail(s) left untouched."):format(r.cod)
  end
  self:EndRun(msg)
end

-- ---------------------------------------------------------------------------
-- Slash interface (/nock mail ...)
-- ---------------------------------------------------------------------------

function Mailbox:PrintReport()
  if self.mailOpen then self:ScanInbox() end
  local r = self.report
  if not self.mailOpen then
    self:Print("Open a mailbox for a snowball report.")
    return
  end
  if not r or r.mails == 0 then
    self:Print("No snowball mail in this inbox.")
    return
  end
  self:Print(("Snowball mail: %d mail(s), %d snowballs. Soonest expiry: %.1f day(s). %d returnable, %d bounce-dead (loot & re-send), %d COD (untouched)."):format(
    r.mails, r.snowballs, r.minDays or 0, r.returnable, r.deleteOnly, r.cod))
  if r.total > r.shown then
    self:Print(("Inbox shows %d of %d mails — the rest trickle in as these are processed."):format(r.shown, r.total))
  end
end

-- Checkpoint probe: the raw API shapes this module depends on.
function Mailbox:DebugDump()
  self:Print(("mail APIs: AutoLoot=%s Take=%s Return=%s CanDelete=%s pending=%s"):format(
    type(AutoLootMailItem), type(TakeInboxItem), type(ReturnInboxItem),
    type(InboxItemCanDelete), tostring(commandPending())))
  local gii = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  local stack = gii and select(8, gii(C.SNOWBALL_ITEM))
  self:Print(("snowball stack max=%s  free general slots=%d  send slots=%d"):format(
    tostring(stack), freeGeneralSlots(), attachSendMax()))
  if not self.mailOpen then
    self:Print("(mailbox closed — open one for inbox fields)")
    return
  end
  local shown, total = GetInboxNumItems()
  self:Print(("inbox shown=%s total=%s"):format(tostring(shown), tostring(total)))
  for i = 1, math.min(shown or 0, 3) do
    local sender, cod, daysLeft, itemCount, wasReturned = mailHeader(i)
    local snow, att = mailSnowballs(i)
    self:Print(("#%d from=%s items=%d snow=%d att=%d cod=%d days=%.1f wasReturned=%s deleteOnly=%s"):format(
      i, tostring(sender), itemCount, snow, att, cod, daysLeft, tostring(wasReturned),
      tostring(InboxItemCanDelete and InboxItemCanDelete(i))))
  end
end

function Mailbox:Command(args)
  local verb, rest = (args or ""):match("^(%S*)%s*(.-)$")
  if verb == "" or verb == "report" then
    self:PrintReport()
  elseif verb == "send" or verb == "sendbags" then
    local bagsOnly = (verb == "sendbags")
    if rest == "bags" then
      bagsOnly, rest = true, ""
    end
    local recipient
    if rest ~= "" then
      recipient = self:MatchRecipient(rest)
      if not recipient then
        self:Print(("'%s' is not on the recipient list (Options → Mailbox)."):format(rest))
        return
      end
    end
    self:StartSend(recipient, bagsOnly)
  elseif verb == "return" then
    self:StartReturn()
  elseif verb == "stop" then
    if self.run then self:Stop() else self:Print("No mailbox run active.") end
  elseif verb == "debug" then
    self:DebugDump()
  else
    self:Print("Usage: /nock mail report | send [name] | sendbags [name] | return | stop")
  end
end
