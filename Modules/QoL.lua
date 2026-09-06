-- Modules/QoL.lua
-- Baseline conveniences (Utilities -> General): the full-screen glow CVar, auto repair and grey selling at a vendor.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local QoL = Nock:NewModule("QoL", "AceEvent-3.0", "AceTimer-3.0", "AceConsole-3.0")

local SELL_BATCH, SELL_GAP = 8, 0.25   -- items per pass, seconds between passes

local function profile()
  return Nock.db and Nock.db.profile or nil
end

-- ---------------------------------------------------------------------------
-- Dual-form container APIs (the modernized client namespaces these under
-- C_Container; keep the bare-global fallback per house style).
-- ---------------------------------------------------------------------------
local function numSlots(bag)
  if C_Container and C_Container.GetContainerNumSlots then return C_Container.GetContainerNumSlots(bag) or 0 end
  if GetContainerNumSlots then return GetContainerNumSlots(bag) or 0 end
  return 0
end

-- -> quality, count, link, locked (nil when the slot is empty)
local function slotInfo(bag, slot)
  if C_Container and C_Container.GetContainerItemInfo then
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not info then return nil end
    return info.quality, info.stackCount or 1, info.hyperlink, info.isLocked or false
  elseif GetContainerItemInfo then
    local _, count, locked, quality, _, _, link = GetContainerItemInfo(bag, slot)
    if not count then return nil end
    return quality, count, link, locked or false
  end
  return nil
end

local function useSlot(bag, slot)
  if C_Container and C_Container.UseContainerItem then C_Container.UseContainerItem(bag, slot)
  elseif UseContainerItem then UseContainerItem(bag, slot) end
end

local function sellPrice(link)
  local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if not (fn and link) then return 0 end
  local price = select(11, fn(link))
  return tonumber(price) or 0
end

local function moneyText(copper)
  if GetCoinTextureString then return GetCoinTextureString(copper) end
  local g = math.floor(copper / 10000)
  local s = math.floor((copper % 10000) / 100)
  local c = copper % 100
  if g > 0 then return ("%dg %ds %dc"):format(g, s, c) end
  if s > 0 then return ("%ds %dc"):format(s, c) end
  return ("%dc"):format(c)
end

-- ---------------------------------------------------------------------------
-- Grey scan: every poor-quality (0) unlocked item in the backpack and the
-- four bags, with what the vendor pays for the stack. Pure apart from the
-- container reads, so the test drives it with stubbed bags.
-- ---------------------------------------------------------------------------
function QoL.ScanGreys()
  local out = {}
  for bag = 0, 4 do
    for slot = 1, numSlots(bag) do
      local quality, count, link, locked = slotInfo(bag, slot)
      if quality == 0 and not locked then
        out[#out + 1] = { bag = bag, slot = slot, value = sellPrice(link) * (count or 1) }
      end
    end
  end
  return out
end

-- ---------------------------------------------------------------------------
-- Selling runs in small passes: the server throttles a burst of merchant
-- sales, and the window may close mid-run.
-- ---------------------------------------------------------------------------
function QoL:SellPass()
  self._sellTimer = nil
  local queue = self._sellQueue
  if not queue or not self._merchantOpen then self._sellQueue = nil; return end
  local n = 0
  while n < SELL_BATCH and #queue > 0 do
    local item = table.remove(queue, 1)
    useSlot(item.bag, item.slot)
    self._sellTotal = (self._sellTotal or 0) + (item.value or 0)
    self._sellCount = (self._sellCount or 0) + 1
    n = n + 1
  end
  if #queue > 0 then
    self._sellTimer = self:ScheduleTimer("SellPass", SELL_GAP)
  else
    self._sellQueue = nil
    if (self._sellCount or 0) > 0 then
      self:Print(("Sold %d grey item%s for %s."):format(self._sellCount, self._sellCount == 1 and "" or "s", moneyText(self._sellTotal or 0)))
    end
    self._sellTotal, self._sellCount = nil, nil
  end
end

function QoL:SellGreys()
  local greys = QoL.ScanGreys()
  if #greys == 0 then return end
  self._sellQueue, self._sellTotal, self._sellCount = greys, 0, 0
  self:SellPass()
end

-- Repair from your own money; never the guild bank.
function QoL:RepairAll()
  if not (CanMerchantRepair and CanMerchantRepair()) then return end
  local cost, canRepair = GetRepairAllCost()
  if not canRepair or not cost or cost <= 0 then return end
  if (GetMoney and GetMoney() or 0) < cost then
    self:Print(("Repair costs %s; not enough money."):format(moneyText(cost)))
    return
  end
  RepairAllItems()
  self:Print(("Repaired for %s."):format(moneyText(cost)))
end

function QoL:MERCHANT_SHOW()
  local p = profile()
  if not p then return end
  self._merchantOpen = true
  if p.qolAutoRepair then self:RepairAll() end
  if p.qolSellGreys then self:SellGreys() end
end

function QoL:MERCHANT_CLOSED()
  self._merchantOpen = false
  if self._sellTimer then self:CancelTimer(self._sellTimer); self._sellTimer = nil end
  if self._sellQueue then
    -- the window closed mid-run: report what did go through
    self._sellQueue = nil
    if (self._sellCount or 0) > 0 then
      self:Print(("Sold %d grey item%s for %s (vendor closed)."):format(self._sellCount, self._sellCount == 1 and "" or "s", moneyText(self._sellTotal or 0)))
    end
    self._sellTotal, self._sellCount = nil, nil
  end
end

-- ---------------------------------------------------------------------------
-- The full-screen glow (ffxGlow). Applied from the profile at login and on
-- every profile switch, written at once when toggled; off restores 1.
-- ---------------------------------------------------------------------------
function QoL:ApplyGlow()
  local p = profile()
  if p and p.qolNoGlow and SetCVar then SetCVar("ffxGlow", "0") end
end

function QoL.SetNoGlow(on)
  local p = profile()
  if p then p.qolNoGlow = on and true or false end
  if SetCVar then SetCVar("ffxGlow", on and "0" or "1") end
end

function QoL:OnEnable()
  self:RegisterEvent("MERCHANT_SHOW")
  self:RegisterEvent("MERCHANT_CLOSED")
  self:RegisterMessage("NOCK_VISUALS_CHANGED", "ApplyGlow")
  self:ApplyGlow()
end
