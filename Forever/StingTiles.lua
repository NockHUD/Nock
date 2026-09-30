-- Forever/StingTiles.lua
-- Sting timers on the cooldown grid: a sting's tile is covered by a one-button aura container on the target, filled by the client.

-- A target's auras are secret in combat and the aura API refuses an addon
-- outright ("Auras cannot be accessed when secret while tainted", probed
-- 2026-09-30), so Nock can never time a sting itself. Blizzard's aura
-- container can: own harmful auras of `target`, filtered to the sting's
-- ranks, one button, drawn by the client with the true countdown (misses,
-- refreshes and other hunters' stings included for free). The container sits
-- on top of the grid slot: sting down, the slot's own lit tile shows through;
-- sting up, the client's icon, swipe and countdown cover it. Nothing is ever
-- read back from a button, and nothing of Nock's anchors TO the container
-- (Forever/AuraRow.lua has both rules). The view (UI/Frame_ReactCooldowns.lua)
-- owns the tiles and calls Sync after a rebuild and RereadAll on a target
-- change.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local ST = {}
Nock.ForeverStingTiles = ST

ST.GROUP  = "sting"
ST.FILTER = "HARMFUL|PLAYER"
-- Frame levels above the slot: clear of its swipes, text layer and glows.
ST.LEVEL_ABOVE = 10

local SLOT_BG = { 0.08, 0.08, 0.08, 1 }

-- Pure: the spell ids a sting's aura can carry. Ranks are separate spells on
-- Forever and some were renumbered, so a candidate rank counts only while the
-- client names it like the sting, and the spellbook's own id for that name
-- (`book`: name -> id) is added.
function ST.Ids(candidates, name, nameOf, book)
  local out, seen = {}, {}
  if type(name) ~= "string" then return out end
  for _, id in ipairs(candidates or {}) do
    if not seen[id] and nameOf(id) == name then
      out[#out + 1] = id
      seen[id] = true
    end
  end
  local bookId = book and book[name]
  if type(bookId) == "number" and not seen[bookId] then out[#out + 1] = bookId end
  return out
end

-- Pure: an id list's fingerprint, whatever its order.
function ST.Signature(ids)
  local sorted = {}
  for i = 1, #ids do sorted[i] = ids[i] end
  table.sort(sorted)
  return table.concat(sorted, ",")
end

local function filtersFor(ids)
  return { includeSpellIDs = Nock.ForeverAuraRow.IdTable(ids) }
end

local function layoutFor(w, h)
  return { elementWidth = w, elementHeight = h, elementSpacing = 0 }
end

-- Size and crop only: safe on a button the client already owns.
local function fitButton(b, w, h, zoom)
  b:SetSize(w, h)
  if b._nockIcon then b._nockIcon:SetTexCoord(Nock.UI.IconCoords(w, h, zoom)) end
end

-- One button over a grid slot: dark ground, the icon inset one unit with the
-- grid's crop, the client's swipe, and its countdown on a layer above the
-- swipe (a Cooldown child paints over its parent's own font strings). No
-- edge of its own: the slot's 1 px border shows around it, shared with the
-- neighbouring tiles (a border drawn here sat on top of that seam and stood
-- out of the grid, user 2026-09-30). Built once per button; the client fills
-- what it is handed.
function ST.Style(b, tile)
  if b._nockStyled then return end
  b._nockStyled = true
  tile.buttons[#tile.buttons + 1] = b
  local ground = b:CreateTexture(nil, "BACKGROUND")
  ground:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
  ground:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
  ground:SetColorTexture(SLOT_BG[1], SLOT_BG[2], SLOT_BG[3], SLOT_BG[4])
  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
  icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
  b._nockIcon = icon
  fitButton(b, tile.w, tile.h, tile.zoom)
  b:SetIcon(icon)

  -- The slot's own swipe look (UI/Widgets.lua CreateIconSlot). Anchored to
  -- the button, not to the icon: the icon is the client's from here on.
  local cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
  cd:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
  cd:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
  cd.noCooldownCount = true
  if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
  if cd.SetDrawEdge then cd:SetDrawEdge(false) end
  if cd.SetSwipeColor then cd:SetSwipeColor(0, 0, 0, 0.75) end
  b:SetDurationCooldown(cd)

  -- The countdown fills the tile and centres inside it: the client sets its
  -- text, so the string must not depend on its own measured size.
  local layer = CreateFrame("Frame", nil, b)
  layer:SetAllPoints(b)
  layer:SetFrameLevel(cd:GetFrameLevel() + 1)
  local time = layer:CreateFontString(nil, "OVERLAY")
  time:SetAllPoints(layer)
  time:SetJustifyH("CENTER")
  time:SetJustifyV("MIDDLE")
  Nock.UI.RegisterFontString(time, "SIZE_OVERLAY", "OUTLINE", true)
  Nock.UI.ApplyReactTextLook(time)
  local fmt = Nock.ForeverAuraRow.DurationFormat()
  if not (fmt and pcall(b.SetDurationText, b, time, fmt)) then b:SetDurationText(time) end

  -- no tooltip over the HUD, and the tile editor's drags reach the slot
  pcall(b.EnableMouse, b, false)
end

-- Build one sting's container on `parent` (the grid). nil on a client
-- without the template or one that refuses the configuration: the sting then
-- keeps its plain tile. Out of combat only (the caller's rule).
function ST.Create(parent, key, w, h, ids, zoom)
  local okc, c = pcall(CreateFrame, "AuraContainer", "NockStingTile" .. key, parent, "CustomAuraContainerTemplate")
  if not okc or not c then return nil end
  local tile = { c = c, key = key, w = w, h = h, zoom = zoom, buttons = {}, sig = ST.Signature(ids) }
  local AU = _G.AnchorUtil or {}
  local axis, dir = AU.FlowLayoutAxis or {}, AU.FlowDirection or {}
  local sort, sdir = _G.AuraContainerSortMethod or {}, _G.AuraContainerSortDirection or {}
  local okb = pcall(function()
    c:SetUnit("target")
    c:SetFlowLayoutAxis(axis.Horizontal or 0)
    c:SetFlowLayoutGrowthDirection(dir.Right or 1, dir.Down or -1)
    c:SetFlowLayoutAnchorPoint("TOPLEFT")
    c:AddAuraGroup(ST.GROUP, ST.FILTER, {
      maxFrameCount = 1,
      candidateFilters = filtersFor(ids),
      -- one button: should the unified tile ever find two of your stings on
      -- a target, it shows the one ending first
      sortMethod = sort.Expiration or 4,
      sortDirection = sdir.Normal or 0,
      initializeFrame = function(b) ST.Style(b, tile) end,
      layout = layoutFor(w, h),
    })
    c:SetEnabled(true)
    c:Show()
  end)
  if not okb then
    pcall(c.Hide, c)
    return nil
  end
  return tile
end

-- Over its slot, above the slot's own layers. Allowed at any time: the
-- container anchors to Nock's frame, never the other way round.
local function place(tile, slot)
  local c = tile.c
  return (pcall(function()
    if tile.slot ~= slot then
      c:ClearAllPoints()
      c:SetPoint("TOPLEFT", slot, "TOPLEFT", 0, 0)
      tile.slot = slot
    end
    c:SetFrameLevel(slot:GetFrameLevel() + ST.LEVEL_ABOVE)
    if tile.parked then
      c:SetEnabled(true)
      c:Show()
      tile.parked = false
      c:UpdateAllAuras()
    end
  end))
end

-- Off the grid: no aura work, nothing drawn.
local function park(tile)
  if tile.parked then return end
  tile.parked, tile.slot = true, nil
  pcall(function()
    tile.c:SetEnabled(false)
    tile.c:Hide()
  end)
end

local function resize(tile, w, h, zoom)
  tile.w, tile.h, tile.zoom = w, h, zoom
  pcall(tile.c.SetAuraGroupLayout, tile.c, ST.GROUP, layoutFor(w, h))
  for i = 1, #tile.buttons do pcall(fitButton, tile.buttons[i], w, h, zoom) end
end

-- New filters reach only auras that change afterwards, so the container is
-- told to re-read what is up now (Forever/AuraRow.lua ApplyFilters).
local function refilter(tile, ids, sig)
  tile.sig = sig
  pcall(tile.c.SetAuraGroupCandidateFilters, tile.c, ST.GROUP, filtersFor(ids))
  pcall(tile.c.UpdateAllAuras, tile.c)
end

-- Bring the view's tiles (`tiles`: entry key -> tile, or false for one the
-- client refused) in line with the grid's slots: every shown slot holding a
-- `debuff` entry gets its container over it, the rest are parked.
-- `env.idsFor(entry)` names the sting's ids. Building, resizing and
-- re-filtering wait for the end of combat: returns true while something
-- waits, so the caller syncs again then.
local live = {}
function ST.Sync(tiles, slots, parent, env)
  local pending = false
  for k in pairs(live) do live[k] = nil end
  for _, slot in ipairs(slots) do
    local e = slot._entry
    if e and e.debuff and slot:IsShown() then
      local w, h = slot:GetWidth(), slot:GetHeight()
      local tile = tiles[e.key]
      if tile == nil then
        if env.inCombat then
          pending = true
        else
          tile = ST.Create(parent, e.key, w, h, env.idsFor(e) or {}, env.zoom) or false
          tiles[e.key] = tile
        end
      end
      if tile then
        live[e.key] = true
        if not place(tile, slot) then pending = pending or env.inCombat end
        if env.inCombat then
          if tile.w ~= w or tile.h ~= h or tile.zoom ~= env.zoom then pending = true end
          -- the ids may have moved too: looked at again after combat
          pending = pending or tile.idsStale == true
        else
          if tile.w ~= w or tile.h ~= h or tile.zoom ~= env.zoom then resize(tile, w, h, env.zoom) end
          local ids = env.idsFor(e) or {}
          local sig = ST.Signature(ids)
          if sig ~= tile.sig then refilter(tile, ids, sig) end
          tile.idsStale = nil
        end
      end
    end
  end
  for key, tile in pairs(tiles) do
    if tile and not live[key] then park(tile) end
  end
  return pending
end

-- The spellbook changed (a new rank): the ids are checked at the next sync.
function ST.MarkIdsStale(tiles)
  for _, tile in pairs(tiles) do
    if tile then tile.idsStale = true end
  end
end

-- A target change: the container follows the unit's aura events, not the
-- token moving to another unit, so each live tile is told to re-read, the
-- way Blizzard's target frame does (TargetFrameMixin:OnEvent).
function ST.RereadAll(tiles)
  for _, tile in pairs(tiles) do
    if tile and not tile.parked then pcall(tile.c.UpdateAllAuras, tile.c) end
  end
end
