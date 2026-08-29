-- UI/Frame_InfoRow.lua
-- Slim bottom strip: pocket-watch icon + ranged weapon speed (left), arrow
-- count + equipped-ammo icon (right). Arrow count = ALL ammo in the quiver/
-- pouch (any type) + equipped-type ammo in regular bags + charges of any items
-- in Constants.ARROW_MAKERS.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local InfoRow = Nock:NewModule("InfoRow", "AceEvent-3.0")
local C = Nock.Constants

local SPEED_ICON          = "Interface\\Icons\\Inv_Misc_PocketWatch_01"
local ARROW_FALLBACK_ICON = "Interface\\Icons\\Inv_Misc_Quiver_05"
local ICON_GAP            = 2

local function getRangedSpeed()
  if UnitRangedDamage then return (UnitRangedDamage("player")) end
  return nil
end

local function getEquippedAmmoId()
  return GetInventoryItemID and GetInventoryItemID("player", 0) or nil
end

local function getEquippedAmmoIcon()
  return (GetInventoryItemTexture and GetInventoryItemTexture("player", 0)) or ARROW_FALLBACK_ICON
end

-- TBC bag family flags: 1 = quiver (arrows-only), 2 = ammo pouch (bullets-only).
-- A regular bag is family 0. We treat both quiver and pouch as "the ammo bag".
local AMMO_BAG_FAMILIES = { [1] = true, [2] = true }

local function getContainerApis()
  if C_Container and C_Container.GetContainerNumFreeSlots then
    return C_Container.GetContainerNumFreeSlots, C_Container.GetContainerNumSlots, C_Container.GetContainerItemInfo, true
  end
  return GetContainerNumFreeSlots, GetContainerNumSlots, GetContainerItemInfo, false
end

-- Number of arrows in the equipped ammo slot (INVSLOT_AMMO = 0). The stack
-- here is the one currently "loaded" — separate from any bag contents.
local function getEquippedSlotCount()
  if not GetInventoryItemCount then return 0 end
  return GetInventoryItemCount("player", 0) or 0
end

-- Total arrows in regular bags only (excludes the equipped slot, excludes the
-- quiver/pouch — we report that separately).
local function getRegularBagCount(ammoId)
  if not ammoId then return 0 end
  local numFree, numSlots, info, isC = getContainerApis()
  if not (numFree and numSlots and info) then return 0 end
  local total = 0
  for bag = 0, 4 do
    local _, family = numFree(bag)
    if not AMMO_BAG_FAMILIES[family or 0] then
      local slots = numSlots(bag) or 0
      for slot = 1, slots do
        local itemId, stack
        if isC then
          local d = info(bag, slot)
          if d then itemId, stack = d.itemID, d.stackCount end
        else
          local _, c, _, _, _, _, _, _, _, id = info(bag, slot)
          itemId, stack = id, c
        end
        if itemId == ammoId then total = total + (stack or 0) end
      end
    end
  end
  return total
end

-- Total ammo in the quiver / ammo-pouch bag (family 1 or 2). A quiver/pouch
-- can ONLY hold ammo, so every stack is counted regardless of item type — this
-- is what makes a mixed quiver (e.g. two arrow types) report the true total
-- instead of only the currently-equipped type. Also returns whether such a bag
-- is equipped; when it isn't, the info row falls back to a single total.
local function getQuiverInfo()
  local numFree, numSlots, info, isC = getContainerApis()
  if not (numFree and numSlots and info) then return 0, false end
  for bag = 0, 4 do
    local _, family = numFree(bag)
    if AMMO_BAG_FAMILIES[family or 0] then
      local slots = numSlots(bag) or 0
      local count = 0
      for slot = 1, slots do
        local stack
        if isC then
          local d = info(bag, slot)
          if d then stack = d.stackCount end
        else
          local _, c = info(bag, slot)
          stack = c
        end
        count = count + (stack or 0)
      end
      return count, true
    end
  end
  return 0, false
end

-- Arrow yield of every projectile-maker carried. These are CHARGED items
-- (e.g. Adamantite Arrow Maker / Shell Machine, 5 charges each). On this client
-- the bag-slot stackCount of a charged item is 1 (NOT its charges), so the
-- containers can't be iterated for charges. GetItemCount(id, false, true) is
-- the correct source: its "include charges" mode returns the true total
-- remaining charges across all of that maker (verified via /nock arrows:
-- 10 makers at 8x5 + 2x3 = 46). multiplier = arrows produced per charge, so
-- charges * multiplier is the makeable-arrow reserve, and it stays stable on
-- use (charge -1 here, +arrows in the quiver counted by getQuiverInfo).
local function getMakerCount()
  local total = 0
  local list = C.ARROW_MAKERS
  if not list then return 0 end
  for _, m in ipairs(list) do
    local n = (GetItemCount and GetItemCount(m.id, false, true)) or 0
    total = total + n * (m.multiplier or 1)
  end
  return total
end

function InfoRow:OnInitialize()
  local parent = Nock.parentFrame
  local h      = C.DIM.INFO_ROW_H
  local innerW = C.DIM.HUD_WIDTH - 2 * C.DIM.OUTER_PAD

  local f = CreateFrame("Frame", "NockInfoRow", parent)
  f:SetSize(innerW, h)

  -- 3px inset on left/right/bottom so the icons don't sit flush against the
  -- HUD's inner margin (the row above already provides the top spacing via the
  -- cooldown slots' internal padding, so top stays flush with the row top).
  local iconSize = h - 3
  local pad      = 3

  -- Left: pocket-watch icon + speed text
  local speedIcon = f:CreateTexture(nil, "ARTWORK")
  speedIcon:SetSize(iconSize, iconSize)
  speedIcon:SetPoint("TOPLEFT", f, "TOPLEFT", pad, 0)
  speedIcon:SetTexture(SPEED_ICON)
  speedIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  f.speedIcon = speedIcon

  local left = f:CreateFontString(nil, "OVERLAY")
  left:SetFont(Nock.UI.GetFont(), C.FONT.SIZE_OVERLAY, "OUTLINE")
  left:SetPoint("LEFT", speedIcon, "RIGHT", ICON_GAP, 0)
  left:SetJustifyH("LEFT")
  left:SetTextColor(unpack(C.COLORS.TEXT))
  f.left = left
  Nock.UI.RegisterFontString(left, "SIZE_OVERLAY", "OUTLINE")

  -- Right: arrow count + equipped-ammo icon
  local arrowIcon = f:CreateTexture(nil, "ARTWORK")
  arrowIcon:SetSize(iconSize, iconSize)
  arrowIcon:SetPoint("TOPRIGHT", f, "TOPRIGHT", -pad, 0)
  arrowIcon:SetTexture(ARROW_FALLBACK_ICON)
  arrowIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  f.arrowIcon = arrowIcon

  local right = f:CreateFontString(nil, "OVERLAY")
  right:SetFont(Nock.UI.GetFont(), C.FONT.SIZE_OVERLAY, "OUTLINE")
  right:SetPoint("RIGHT", arrowIcon, "LEFT", -ICON_GAP, 0)
  right:SetJustifyH("RIGHT")
  right:SetTextColor(unpack(C.COLORS.TEXT))
  f.right = right
  Nock.UI.RegisterFontString(right, "SIZE_OVERLAY", "OUTLINE")

  self.frame          = f
  self._lastLeft      = ""
  self._lastRight     = ""
  self._lastArrowIcon = ARROW_FALLBACK_ICON
  self._arrows        = 0

  self:RegisterEvent("BAG_UPDATE_DELAYED")
  self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
  self:RegisterEvent("PLAYER_LOGIN")
  self:RegisterEvent("PLAYER_ENTERING_WORLD")
  self:RefreshArrows()
end

function InfoRow:RefreshArrows()
  local ammoId = getEquippedAmmoId()
  local quiverCount, hasQuiver = getQuiverInfo()
  local bagCount   = ammoId and getRegularBagCount(ammoId) or 0
  local makerCount = getMakerCount()

  -- On Anniversary TBC the ammo-slot stack and the quiver share the same
  -- inventory bucket — querying both via GetInventoryItemCount + GetItemCount
  -- ends up double-counting. Trust the bag iteration (which sees quiver +
  -- regular bags as distinct families) and the maker conversion only.
  self._totalArrows  = quiverCount + bagCount + makerCount
  self._quiverArrows = quiverCount
  self._hasQuiver    = hasQuiver

  -- Publish to shared state so the ShoppingList (and anything else) can read
  -- the true ammo reserve without recomputing it.
  local a = Nock.state and Nock.state.ammo
  if a then
    a.total     = self._totalArrows
    a.quiver    = quiverCount
    a.hasQuiver = hasQuiver
  end

  local icon = getEquippedAmmoIcon()
  if icon ~= self._lastArrowIcon then
    self.frame.arrowIcon:SetTexture(icon)
    self._lastArrowIcon = icon
  end
end

-- /nock arrows — raw container dump so ammo/maker math can be verified against
-- the real client instead of guessed. Builds one plain-text block and pushes it
-- through geterrorhandler() so BugGrabber/BugSack captures it as a single
-- copy-pasteable entry (timestamped so repeat runs aren't deduped into "x2").
function InfoRow:DumpArrows()
  local lines = {}
  local function add(s) lines[#lines + 1] = s end

  local numFree, numSlots, info, isC = getContainerApis()
  add(("Nock arrows dump @ %s  API=%s"):format(
    (date and date("%H:%M:%S")) or tostring(GetTime()),
    isC and "C_Container" or "legacy"))

  if not (numFree and numSlots and info) then
    add("  container API unavailable")
  else
    local makerSet = {}
    if C.ARROW_MAKERS then
      for _, m in ipairs(C.ARROW_MAKERS) do makerSet[m.id] = m.multiplier or 1 end
    end

    local ammoId = getEquippedAmmoId()
    for bag = 0, 4 do
      local _, family = numFree(bag)
      local slots = numSlots(bag) or 0
      add(("bag %d  family=%s  slots=%d%s%s"):format(
        bag, tostring(family), slots,
        AMMO_BAG_FAMILIES[family or 0] and "  [AMMO BAG]" or "",
        (family or 0) == 0 and "  [regular]" or ""))
      for slot = 1, slots do
        local itemId, stack, link
        if isC then
          local d = info(bag, slot)
          if d then itemId, stack, link = d.itemID, d.stackCount, d.hyperlink end
        else
          local _, c, _, _, _, _, lnk, _, _, id = info(bag, slot)
          itemId, stack, link = id, c, lnk
        end
        if itemId then
          local name = (GetItemInfo and GetItemInfo(itemId)) or link or "?"
          local tag = (itemId == ammoId and " <EQUIPPED-AMMO>")
                   or (makerSet[itemId] and (" <MAKER x%d>"):format(makerSet[itemId]))
                   or ""
          add(("   slot %d: id=%s stack=%s %s%s"):format(
            slot, tostring(itemId), tostring(stack), tostring(name), tag))
        end
      end
    end

    local quiverCount, hasQuiver = getQuiverInfo()
    local bagCount   = ammoId and getRegularBagCount(ammoId) or 0
    local makerCount = getMakerCount()
    add(("equipped ammo: id=%s  slotCount=%s"):format(
      tostring(ammoId), tostring(getEquippedSlotCount())))
    if C.ARROW_MAKERS then
      for _, m in ipairs(C.ARROW_MAKERS) do
        local gc  = GetItemCount and GetItemCount(m.id) or 0
        local gcc = GetItemCount and GetItemCount(m.id, false, true) or 0
        add(("maker %d: GetItemCount=%s  +charges=%s  (x%d)"):format(
          m.id, tostring(gc), tostring(gcc), m.multiplier or 1))
      end
    end
    add(("TOTALS  quiver=%d (has=%s)  regBag=%d  maker=%d  =>  %d"):format(
      quiverCount, tostring(hasQuiver), bagCount, makerCount,
      quiverCount + bagCount + makerCount))
  end

  local out = table.concat(lines, "\n")
  local eh = geterrorhandler and geterrorhandler()
  if eh then
    eh(out)
    Nock:Print("Arrow dump sent to BugSack — open it and copy the latest entry.")
  else
    -- No error handler (no BugGrabber): fall back to chat, line by line.
    for _, ln in ipairs(lines) do Nock:Print(ln) end
  end
end

function InfoRow:BAG_UPDATE_DELAYED()       self:RefreshArrows() end
function InfoRow:PLAYER_EQUIPMENT_CHANGED() self:RefreshArrows() end
function InfoRow:PLAYER_LOGIN()             self:RefreshArrows() end
function InfoRow:PLAYER_ENTERING_WORLD()    self:RefreshArrows() end

function InfoRow:Refresh(state)
  local speed = getRangedSpeed()
  local leftTxt = speed and ("%.2fs"):format(speed) or ""
  if leftTxt ~= self._lastLeft then
    self.frame.left:SetText(leftTxt)
    self._lastLeft = leftTxt
  end

  -- "<quiver> / <total>" when a quiver/pouch is equipped; total only otherwise.
  local rightTxt
  if self._hasQuiver then
    rightTxt = ("%d/%d"):format(self._quiverArrows or 0, self._totalArrows or 0)
  else
    rightTxt = tostring(self._totalArrows or 0)
  end
  if rightTxt ~= self._lastRight then
    self.frame.right:SetText(rightTxt)
    self._lastRight = rightTxt
  end
end
