-- Modules/QoL.lua
-- Baseline conveniences (Utilities -> General): the full-screen glow CVar, auto repair and grey selling at a vendor.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local QoL = Nock:NewModule("QoL", "AceEvent-3.0", "AceTimer-3.0", "AceConsole-3.0")

-- Camera & world quick toggles (Utilities -> Quality of life). These are the
-- client's own CVars, read and written live: the client keeps them per
-- character, so Nock stores nothing and never re-applies. Pure over
-- GetCVar/SetCVar so the page can be tested without a client.
local QoLCvar = {
  FOG    = "volumeFog",                    -- 1 on, 0 off
  CAMERA = "cameraSmoothStyle",            -- Blizzard's "Camera Following Style"
  ZOOM   = "cameraDistanceMaxZoomFactor",  -- 1.0 .. the client's cap (2.6 on this client, 4 on old ones)
  SPEECH = "Sound_EnableErrorSpeech",      -- the spoken "I can't do that yet"; 1 on, 0 off
  CAMERA_STYLES = {
    ["0"] = "Never adjust camera",
    ["1"] = "Adjust camera only horizontally when moving",
    ["4"] = "Adjust camera only when moving",
    ["2"] = "Always adjust camera",
  },
  CAMERA_ORDER   = { "0", "1", "4", "2" },
  CAMERA_DEFAULT = "4",
  ZOOM_NEAR = 1.9,   -- Blizzard's default
  ZOOM_FAR  = 2.6,   -- the far cap on this client
}
Nock.QoLCvar = QoLCvar

local function cvarGet(name)
  local G = _G.GetCVar
  if not G then return nil end
  local okc, v = pcall(G, name)
  return okc and v or nil
end

local function cvarSet(name, value)
  local S = _G.SetCVar
  if S then pcall(S, name, value) end
end

function QoLCvar.GetBool(name)
  local v = cvarGet(name)
  return v == "1" or v == 1 or v == true
end

function QoLCvar.SetBool(name, on)
  cvarSet(name, on and "1" or "0")
end

function QoLCvar.GetChoice(name, choices)
  local v = cvarGet(name)
  v = v ~= nil and tostring(v) or nil
  if v and choices[v] then return v end
  return QoLCvar.CAMERA_DEFAULT
end

function QoLCvar.SetChoice(name, value)
  cvarSet(name, tostring(value))
end

function QoLCvar.GetNumber(name, fallback)
  local v = tonumber(cvarGet(name))
  return v or fallback
end

function QoLCvar.SetNumber(name, value)
  cvarSet(name, ("%.1f"):format(tonumber(value) or 0))
end

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
  if _G.GetContainerNumSlots then return _G.GetContainerNumSlots(bag) or 0 end
  return 0
end

-- -> quality, count, link, locked (nil when the slot is empty)
local function slotInfo(bag, slot)
  if C_Container and C_Container.GetContainerItemInfo then
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not info then return nil end
    return info.quality, info.stackCount or 1, info.hyperlink, info.isLocked or false
  elseif _G.GetContainerItemInfo then
    local _, count, locked, quality, _, _, link = _G.GetContainerItemInfo(bag, slot)
    if not count then return nil end
    return quality, count, link, locked or false
  end
  return nil
end

local function useSlot(bag, slot)
  if C_Container and C_Container.UseContainerItem then C_Container.UseContainerItem(bag, slot)
  elseif _G.UseContainerItem then _G.UseContainerItem(bag, slot) end
end

local function sellPrice(link)
  local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if not (fn and link) then return 0 end
  local price = select(11, fn(link))
  return tonumber(price) or 0
end

local function moneyText(copper)
  if _G.GetCoinTextureString then return _G.GetCoinTextureString(copper) end
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

-- ---------------------------------------------------------------------------
-- Ammo restock: fill the quiver / ammo pouch with the LOADED ammo (ammo slot
-- 0) from the vendor's list. Only that bag, only that item: regular bags are
-- never touched, another arrow type in the quiver keeps its slot. The plan is
-- pure over a reads table so the test drives it without a client:
--   ammoId, ammoSubclass   the loaded ammo (false/nil = nothing loaded)
--   stackSize              its max stack
--   quiverSlots, quiver    slot count and { [slot] = { id, count } } (empty
--                          slots absent), bagFamily 1 = quiver, 2 = pouch
--   vendor                 { { index, id, price, bundle, available } }:
--                          price is per BUNDLE (the vendor's stack, e.g. 200
--                          Heavy Shot for 50c), available -1 = unlimited,
--                          otherwise bundles in stock
--   money                  copper on hand
--   maxPerBuy              the vendor's per-purchase cap in items (optional)
-- -> { buys = { { index, count, cost } }, units, cost }
-- BuyMerchantItem's quantity is a number of ITEMS whether or not the vendor
-- sells in stacks (since 4.1; the bundle count was the pre-4.1 reading, and
-- sending it here bought three single shots). One buy per slot gap, split
-- only by the per-purchase cap; the cost is the per-item share of the bundle
-- price, rounded up.
-- ---------------------------------------------------------------------------
local ITEM_CLASS_PROJECTILE = (C and C.ITEM_CLASS_PROJECTILE) or 6
local BAG_FAMILY_FOR_AMMO   = {            -- projectile subclass -> bag family
  [(C and C.PROJECTILE_ARROW)  or 2] = 1,  -- arrows  -> quiver
  [(C and C.PROJECTILE_BULLET) or 3] = 2,  -- bullets -> ammo pouch
}
local BUY_GAP = 0.25   -- seconds between purchases (the server throttles bursts)

function QoL.PlanAmmoRestock(r)
  local plan = { buys = {}, units = 0, cost = 0 }
  local id, stack = r.ammoId, tonumber(r.stackSize) or 0
  if not id or stack <= 0 or (r.quiverSlots or 0) <= 0 then return plan end
  local want = r.ammoSubclass and BAG_FAMILY_FOR_AMMO[r.ammoSubclass]
  if want and r.bagFamily and r.bagFamily ~= want then return plan end
  local row
  for _, v in ipairs(r.vendor or {}) do
    if v.id == id then row = v; break end
  end
  if not row or (row.price or 0) <= 0 or (row.bundle or 1) <= 0 then return plan end
  local bundle = row.bundle or 1
  local perItem = row.price / bundle
  local left = math.floor((r.money or 0) / perItem)               -- items affordable
  if row.available and row.available >= 0 then left = math.min(left, row.available * bundle) end
  local cap = tonumber(r.maxPerBuy) or 0
  if cap <= 0 then cap = stack end
  for slot = 1, r.quiverSlots do
    if left <= 0 then break end
    local s = r.quiver and r.quiver[slot]
    local gap = 0
    if not s then gap = stack
    elseif s.id == id then gap = stack - (s.count or 0) end
    while gap > 0 and left > 0 do
      local n = math.min(gap, left, cap)
      local cost = math.ceil(n * perItem)
      plan.buys[#plan.buys + 1] = { index = row.index, count = n, cost = cost }
      plan.units = plan.units + n
      plan.cost  = plan.cost + cost
      gap, left = gap - n, left - n
    end
  end
  return plan
end

-- The equipped quiver / pouch: bag index, slot count, family (nil = none).
local function findAmmoBag()
  local free = (C_Container and C_Container.GetContainerNumFreeSlots) or _G.GetContainerNumFreeSlots
  if not free then return nil end
  for bag = 0, 4 do
    local _, family = free(bag)
    if family == 1 or family == 2 then return bag, numSlots(bag), family end
  end
  return nil
end

-- -> itemID, count (nil when the slot is empty)
local function slotItem(bag, slot)
  if C_Container and C_Container.GetContainerItemInfo then
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not info then return nil end
    return info.itemID, info.stackCount or 1
  elseif _G.GetContainerItemID then
    local id = _G.GetContainerItemID(bag, slot)
    if not id then return nil end
    local _, count = _G.GetContainerItemInfo(bag, slot)
    return id, count or 1
  end
  return nil
end

local function merchantItemId(i)
  if _G.GetMerchantItemID then return _G.GetMerchantItemID(i) end
  local link = _G.GetMerchantItemLink and _G.GetMerchantItemLink(i)
  return link and tonumber(link:match("item:(%d+)")) or nil
end

-- One vendor row -> name, price, bundle (units per purchase), numAvailable
-- (-1 = unlimited), purchasable. The bare GetMerchantItemInfo is deprecated
-- (11.0.5) and nil on Forever; C_MerchantFrame.GetItemInfo returns a table.
local function merchantRow(i)
  if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
    local t = C_MerchantFrame.GetItemInfo(i)
    if not t then return nil end
    return t.name, t.price, t.stackCount, t.numAvailable, t.isPurchasable
  elseif _G.GetMerchantItemInfo then
    local name, _, price, bundle, available, purchasable = _G.GetMerchantItemInfo(i)
    return name, price, bundle, available, purchasable
  end
  return nil
end

local function readAmmoRestock()
  local r = { vendor = {}, quiver = {}, money = _G.GetMoney and _G.GetMoney() or 0 }
  r.ammoId = _G.GetInventoryItemID and _G.GetInventoryItemID("player", 0) or false
  if not r.ammoId then return r end
  local instant = (C_Item and C_Item.GetItemInfoInstant) or _G.GetItemInfoInstant
  if instant then
    local _, _, _, _, _, classID, subclassID = instant(r.ammoId)
    if classID == ITEM_CLASS_PROJECTILE then r.ammoSubclass = subclassID end
  end
  local info = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
  if info then
    local name, _, _, _, _, _, _, stack = info(r.ammoId)
    r.ammoName, r.stackSize = name, stack
  end
  local bag, slots, family = findAmmoBag()
  r.bag, r.quiverSlots, r.bagFamily = bag, slots or 0, family
  if bag then
    for slot = 1, slots do
      local id, count = slotItem(bag, slot)
      if id then r.quiver[slot] = { id = id, count = count } end
    end
  end
  local n = _G.GetMerchantNumItems and _G.GetMerchantNumItems() or 0
  for i = 1, n do
    local name, price, bundle, available, purchasable = merchantRow(i)
    if name ~= nil and purchasable ~= false then
      local rowId = merchantItemId(i)
      r.vendor[#r.vendor + 1] = { index = i, id = rowId, name = name, price = price, bundle = bundle, available = available }
      if rowId == r.ammoId and _G.GetMerchantItemMaxStack then r.maxPerBuy = _G.GetMerchantItemMaxStack(i) end
    end
  end
  return r
end

function QoL:BuyPass()
  self._buyTimer = nil
  local queue = self._buyQueue
  if not queue or not self._merchantOpen then self._buyQueue = nil; return end
  local b = table.remove(queue, 1)
  if b and _G.BuyMerchantItem then
    _G.BuyMerchantItem(b.index, b.count)
    self._buyUnits = (self._buyUnits or 0) + b.count
    self._buyCost  = (self._buyCost or 0) + b.cost
  end
  if #queue > 0 then
    self._buyTimer = self:ScheduleTimer("BuyPass", BUY_GAP)
  else
    self:FinishRestock(nil)
  end
end

function QoL:FinishRestock(note)
  self._buyQueue = nil
  if (self._buyUnits or 0) > 0 then
    self:Print(("Bought %d %s for %s%s."):format(self._buyUnits, self._buyName or "ammo", moneyText(self._buyCost or 0), note or ""))
  end
  self._buyUnits, self._buyCost, self._buyName = nil, nil, nil
end

-- /nock restock: the reads and the plan as the runner sees them, in a copybox
-- (open a vendor first). Diagnostic only; buys nothing.
function QoL:DumpRestock()
  local r = readAmmoRestock()
  local plan = QoL.PlanAmmoRestock(r)
  local out = {}
  local function add(fmt, ...) out[#out + 1] = fmt:format(...) end
  add("merchantOpen=%s  toggle=%s  money=%s", tostring(self._merchantOpen), tostring(profile() and profile().qolRestockAmmo), tostring(r.money))
  add("ammo: id=%s name=%s subclass=%s stack=%s", tostring(r.ammoId), tostring(r.ammoName), tostring(r.ammoSubclass), tostring(r.stackSize))
  add("bag=%s slots=%s family=%s  maxPerBuy=%s", tostring(r.bag), tostring(r.quiverSlots), tostring(r.bagFamily), tostring(r.maxPerBuy))
  for slot = 1, r.quiverSlots or 0 do
    local q = r.quiver[slot]
    add("  slot %d: %s", slot, q and ("id=%s x%s"):format(tostring(q.id), tostring(q.count)) or "empty")
  end
  add("vendor: %d rows (GetMerchantNumItems=%s, GetMerchantItemID=%s, GetMerchantItemLink=%s, C_MerchantFrame.GetItemInfo=%s, BuyMerchantItem=%s)", #r.vendor,
    tostring(_G.GetMerchantNumItems and _G.GetMerchantNumItems()), tostring(_G.GetMerchantItemID ~= nil), tostring(_G.GetMerchantItemLink ~= nil),
    tostring(C_MerchantFrame and C_MerchantFrame.GetItemInfo ~= nil), tostring(_G.BuyMerchantItem ~= nil))
  for _, v in ipairs(r.vendor) do
    add("  [%d] id=%s %s price=%s bundle=%s avail=%s", v.index, tostring(v.id), tostring(v.name), tostring(v.price), tostring(v.bundle), tostring(v.available))
  end
  add("plan: %d buys, %d units, %d copper", #plan.buys, plan.units, plan.cost)
  for _, b in ipairs(plan.buys) do add("  buy index=%d items=%d cost=%d", b.index, b.count, b.cost) end
  local text = table.concat(out, "\n")
  if Nock.UI and Nock.UI.ShowCopyBox then Nock.UI.ShowCopyBox(text) else self:Print(text) end
end

function QoL:RestockAmmo()
  local r = readAmmoRestock()
  local plan = QoL.PlanAmmoRestock(r)
  if #plan.buys == 0 then return end
  self._buyQueue, self._buyUnits, self._buyCost, self._buyName = plan.buys, 0, 0, r.ammoName
  self:BuyPass()
end

function QoL:MERCHANT_SHOW()
  local p = profile()
  if not p then return end
  self._merchantOpen = true
  if p.qolAutoRepair then self:RepairAll() end
  if p.qolSellGreys then self:SellGreys() end
  if p.qolRestockAmmo then self:RestockAmmo() end
end

function QoL:MERCHANT_CLOSED()
  self._merchantOpen = false
  if self._sellTimer then self:CancelTimer(self._sellTimer); self._sellTimer = nil end
  if self._buyTimer then self:CancelTimer(self._buyTimer); self._buyTimer = nil end
  if self._buyQueue then self:FinishRestock(" (vendor closed)") end
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

-- ---------------------------------------------------------------------------
-- Error text (Forever only; the profile is shared with Anniversary, so the
-- flag is ignored there). The red "You have no target" text lands on the
-- warnings row: UIErrorsFrame stops listening to UI_ERROR_MESSAGE while
-- qolHideErrors is on. Off hands the event back only if Nock took it, so an
-- error addon that owns the frame is never undone. Yellow info text stays.
-- (First version hides every error; a curated list is planned.)
-- ---------------------------------------------------------------------------
function QoL:ApplyErrors()
  local f = _G.UIErrorsFrame
  if not (f and f.UnregisterEvent) then return end
  local p = profile()
  local forever = Nock.Flavor and Nock.Flavor.forever
  local want = (forever and p and p.qolHideErrors) and true or false
  if want and not self._errorsTaken then
    if f.IsEventRegistered and not f:IsEventRegistered("UI_ERROR_MESSAGE") then return end
    f:UnregisterEvent("UI_ERROR_MESSAGE")
    self._errorsTaken = true
  elseif not want and self._errorsTaken then
    f:RegisterEvent("UI_ERROR_MESSAGE")
    self._errorsTaken = false
  end
end

function QoL.SetHideErrors(on)
  local p = profile()
  if p then p.qolHideErrors = on and true or false end
  QoL:ApplyErrors()
end

function QoL:ApplyProfile()
  self:ApplyGlow()
  self:ApplyErrors()
end

function QoL:OnEnable()
  self:RegisterEvent("MERCHANT_SHOW")
  self:RegisterEvent("MERCHANT_CLOSED")
  self:RegisterMessage("NOCK_VISUALS_CHANGED", "ApplyProfile")
  self:ApplyProfile()
end
