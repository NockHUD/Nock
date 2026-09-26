-- Forever/AuraRow.lua
-- The client-drawn half of the Forever buff row: Blizzard's aura container
-- shows the player's own SHORT helpful auras (procs, cooldown buffs) with
-- their true countdowns, in combat too, without Nock ever reading an aura.
-- Proven 2026-09-23 (`/nock probe container`): a CustomAuraButtonTemplate
-- button draws nothing until it is handed regions, and everything it is
-- handed becomes secret-sticky, so the buttons are built here once and
-- never read back. The ledger (Forever/Buffs.lua) keeps what the container
-- cannot reach: buffs on the pet, and the happiness face.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local AuraRow = {}
Nock.ForeverAuraRow = AuraRow

-- Auras whose FULL duration is longer than this are noise on a HUD (aspects,
-- Shadowmeld, food, flasks, scrolls); any cap also hides permanent auras.
AuraRow.MAX_DURATION = 60
AuraRow.MAX_FRAMES   = 8
AuraRow.GROUP        = "short"
-- The user's pinned buffs (reactBuffCustom): shown whatever their duration
-- and whoever cast them (a flask, an aspect, a shaman's totem buff), after
-- the short ones. The hide list (foreverBuffHide) drops IDs from the short
-- group; pinned IDs are dropped from it too so nothing shows twice.
AuraRow.PIN_GROUP    = "pinned"
AuraRow.PIN_FRAMES   = 4
-- How the container wants an ID list: "set" ({ [id] = true }, EverAuras) or
-- "list" ({ id, id }). "set" verified in-game 2026-09-26 (Quick Shots hidden);
-- `/nock probe idshape set|list` flips it live.
AuraRow.ID_SHAPE     = "set"
-- The pet line above the client row: Nock's own tiles (Mend, Feed, the
-- happiness face), smaller, centred by Nock since it knows their count.
AuraRow.PET_ICON = 20
AuraRow.LINE_GAP = 2

local SLOT_BG = { 0.08, 0.08, 0.08, 1 }

-- The countdown as a bare number. The client's default binding prints
-- "12 s"; a numeric rule formatter over the remaining duration (whole
-- seconds, rounded up like the default) through the button's textFormat
-- option prints "12". Built once; nil where the client lacks the APIs.
function AuraRow.DurationFormat()
  if AuraRow._durationFormat ~= nil then return AuraRow._durationFormat or nil end
  local SU, E = _G.C_StringUtil, _G.Enum
  local prop = E and E.DurationTextBindingProperty and E.DurationTextBindingProperty.RemainingDuration
  local up = E and E.NumericRuleFormatRounding and E.NumericRuleFormatRounding.Up
  if not (SU and SU.CreateNumericRuleFormatter and prop and up) then AuraRow._durationFormat = false; return nil end
  local okc, f = pcall(SU.CreateNumericRuleFormatter)
  if not (okc and f and f.AddBreakpoint) then AuraRow._durationFormat = false; return nil end
  local okb = pcall(f.AddBreakpoint, f, { threshold = 0, step = 1, rounding = up, format = "%d" })
  if not okb then AuraRow._durationFormat = false; return nil end
  AuraRow._durationFormat = { textFormat = { formatString = "{}", components = { { property = prop, formatter = f } } } }
  return AuraRow._durationFormat
end

-- One button in the HUD's tile look: black 1 px edge, dark ground, the icon
-- inset one unit with the spell-icon crop, the countdown centred in the
-- React font. `time`/`label` are named so SetReactSlotSize can size the
-- fonts the way it does for the ledger tiles.
function AuraRow.Style(b, size)
  if b._nockStyled then return end
  b._nockStyled = true
  local edge = b:CreateTexture(nil, "BACKGROUND", nil, -1)
  edge:SetAllPoints(b)
  edge:SetColorTexture(0, 0, 0, 1)
  local ground = b:CreateTexture(nil, "BACKGROUND")
  ground:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
  ground:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
  ground:SetColorTexture(SLOT_BG[1], SLOT_BG[2], SLOT_BG[3], SLOT_BG[4])
  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
  icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  -- The countdown fills the tile and centres inside it: the client sets
  -- its text, so the string must not depend on its own measured size for
  -- the centre (a self-sized string sat up-left, 2026-09-23).
  local time = b:CreateFontString(nil, "OVERLAY")
  time:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
  time:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
  time:SetJustifyH("CENTER")
  time:SetJustifyV("MIDDLE")
  local label = b:CreateFontString(nil, "OVERLAY")
  label:SetPoint("BOTTOM", b, "BOTTOM", 0, 1)
  b.time, b.label = time, label
  b._timeBoxed = true  -- SetReactSlotSize nudges both corners, not a centre
  if Nock.UI and Nock.UI.SetReactSlotSize then Nock.UI.SetReactSlotSize(b, size) else b:SetSize(size, size) end
  b:SetIcon(icon)
  local fmt = AuraRow.DurationFormat()
  if not (fmt and pcall(b.SetDurationText, b, time, fmt)) then b:SetDurationText(time) end
end

-- The container's width is a secret in combat, but the CLIENT places a frame
-- from its anchor and its own size: anchored by its bottom centre to the
-- row's bottom centre, the container centres itself. Set once. Nothing of
-- Nock's may anchor TO the container ("dependent object would inherit
-- forbidden aspects: UntrustedLayoutScriptExecution", 2026-09-23), so the
-- ledger tiles sit at the row's left edge instead; they meet the client's
-- tiles only with six or more of those up at once.
function AuraRow.Anchor(c, panel)
  if c._nockAnchored then return end
  c._nockAnchored = true
  c:ClearAllPoints()
  c:SetPoint("BOTTOM", panel, "BOTTOM", 0, 0)
end

-- Two lines: the client's row at the bottom, the pet line above it.
function AuraRow.LineHeight(rowIcon, petIcon)
  return rowIcon + AuraRow.LINE_GAP + (petIcon or AuraRow.PET_ICON)
end

-- x of tile `i` of `n` on a centred line of `w` units.
function AuraRow.TileX(i, n, size, gap, w)
  local totalW = n * size + (n - 1) * gap
  return (w - totalW) / 2 + (i - 1) * (size + gap)
end

function AuraRow.AnchorTile(slot, panel, x, y)
  slot:ClearAllPoints()
  slot:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", x, y)
end

-- An ID table in the container's shape from a profile list (numbers or
-- numeric strings; junk skipped, duplicates folded).
function AuraRow.IdTable(list, shape)
  local out, seen = {}, {}
  if type(list) == "table" then
    for i = 1, #list do
      local id = tonumber(list[i])
      if id and not seen[id] then
        seen[id] = true
        if (shape or AuraRow.ID_SHAPE) == "list" then out[#out + 1] = id else out[id] = true end
      end
    end
  end
  return out
end

-- The two groups' candidate filters from the hide and pin lists. An empty
-- include list shows nothing, which is what an empty pin list means.
function AuraRow.Filters(hide, pin, shape)
  local short = { maxDuration = AuraRow.MAX_DURATION }
  local both = {}
  if type(hide) == "table" then for i = 1, #hide do both[#both + 1] = hide[i] end end
  if type(pin) == "table" then for i = 1, #pin do both[#both + 1] = pin[i] end end
  if #both > 0 then short.excludeSpellIDs = AuraRow.IdTable(both, shape) end
  return short, { includeSpellIDs = AuraRow.IdTable(pin, shape) }
end

-- Would the short group show this aura on its own? Own, timed, short.
function AuraRow.ShownByRule(a)
  local d = tonumber(a and a.duration)
  return a ~= nil and a.sourceUnit == "player" and d ~= nil and d > 0 and d <= AuraRow.MAX_DURATION
end

-- The settings' "Buffs up now" list from out-of-combat aura records
-- (AuraData shape): helpful ones, one line per spell id, each with where it
-- stands: `rule` (the row shows it by itself), `pinned`, `hidden`. Lines the
-- row shows come first, then by name. Pure.
function AuraRow.Candidates(auras, pinList, hideList)
  local pin, hide = AuraRow.IdTable(pinList, "set"), AuraRow.IdTable(hideList, "set")
  local out, seen = {}, {}
  for i = 1, #(auras or {}) do
    local a = auras[i]
    local id = a and tonumber(a.spellId)
    if id and a.isHelpful ~= false and not seen[id] then
      seen[id] = true
      out[#out + 1] = { id = id, name = a.name or ("Spell " .. id), icon = a.icon,
                        rule = AuraRow.ShownByRule(a), pinned = pin[id] or false, hidden = hide[id] or false }
    end
  end
  table.sort(out, function(x, y)
    if x.rule ~= y.rule then return x.rule end
    if x.name ~= y.name then return x.name < y.name end
    return x.id < y.id
  end)
  return out
end

-- A typed entry to an ID: digits are the id; a name is first looked up
-- among the buffs up now (the AURA's own id), then as a spell. nil if
-- neither knows it. `auraByName(name)` -> record, `spellByName(name)` -> id.
function AuraRow.ResolveEntry(text, auraByName, spellByName)
  local s = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if s == "" then return nil end
  if s:match("^%d+$") then return tonumber(s) end
  local a = auraByName and auraByName(s)
  if a and tonumber(a.spellId) then return tonumber(a.spellId) end
  local id = spellByName and spellByName(s)
  return tonumber(id)
end

-- `list` with `id` added (once) or removed; a new array, the input untouched.
function AuraRow.ListWith(list, id, add)
  local out = {}
  for i = 1, #(list or {}) do
    local v = tonumber(list[i])
    if v and v ~= id then out[#out + 1] = v end
  end
  if add then out[#out + 1] = id end
  return out
end

-- Re-filter a built container (a list changed). Out of combat only: the
-- caller defers a change made in combat. New filters reach only auras that
-- change afterwards, so the container is told to re-read what is up now
-- (Plater and EverAuras do the same). False if the client refused;
-- AuraRow.lastApply says which step, for `/nock probe idshape`.
function AuraRow.ApplyFilters(c, hide, pin)
  local short, pinned = AuraRow.Filters(hide, pin)
  local ok1, e1 = pcall(c.SetAuraGroupCandidateFilters, c, AuraRow.GROUP, short)
  local ok2, e2 = true, nil
  if c._nockPinned then ok2, e2 = pcall(c.SetAuraGroupCandidateFilters, c, AuraRow.PIN_GROUP, pinned) end
  local ok3, e3 = pcall(c.UpdateAllAuras, c)
  local function say(ok, e) return ok and "ok" or ("error: " .. tostring(e)) end
  AuraRow.lastApply = ("short filters %s; pinned filters %s; refresh %s"):format(
    say(ok1, e1), c._nockPinned and say(ok2, e2) or "no pinned group", say(ok3, e3))
  return ok1 and ok2
end

-- Every button the container built, both groups (for restyling).
function AuraRow.EachButton(c, fn)
  pcall(function()
    for i = 1, AuraRow.MAX_FRAMES do
      local b = c:GetAuraGroupFrame(AuraRow.GROUP, i)
      if b then fn(b) end
    end
    if c._nockPinned then
      for i = 1, AuraRow.PIN_FRAMES do
        local b = c:GetAuraGroupFrame(AuraRow.PIN_GROUP, i)
        if b then fn(b) end
      end
    end
  end)
end

-- Build the container on `parent`. nil on a client without the template (the
-- row then shows the ledger alone). Every client call is guarded: a refusal
-- costs the row, never the HUD; a refused pinned group costs only the pins.
function AuraRow.Create(parent, size, gap, hide, pin)
  local okc, c = pcall(CreateFrame, "AuraContainer", "NockForeverAuraRow", parent, "CustomAuraContainerTemplate")
  if not okc or not c then return nil end
  local AU = _G.AnchorUtil or {}
  local axis = AU.FlowLayoutAxis or {}
  local dir  = AU.FlowDirection or {}
  local sort = _G.AuraContainerSortMethod or {}
  local sdir = _G.AuraContainerSortDirection or {}
  local short, pinned = AuraRow.Filters(hide, pin)
  local function opts(maxFrames, filters)
    return {
      maxFrameCount = maxFrames,
      candidateFilters = filters,
      sortMethod = sort.Expiration or 4,
      sortDirection = sdir.Normal or 0,
      initializeFrame = function(b) AuraRow.Style(b, size) end,
      layout = { elementWidth = size, elementHeight = size, elementSpacing = gap },
    }
  end
  local ok2 = pcall(function()
    c:SetUnit("player")
    c:SetFlowLayoutAxis(axis.Horizontal or 0)
    c:SetFlowLayoutGrowthDirection(dir.Right or 1, dir.Down or -1)
    c:SetFlowLayoutAnchorPoint("BOTTOMLEFT")
    c:AddAuraGroup(AuraRow.GROUP, "HELPFUL|PLAYER", opts(AuraRow.MAX_FRAMES, short))
  end)
  if not ok2 then
    c:Hide()
    return nil
  end
  c._nockPinned = pcall(c.AddAuraGroup, c, AuraRow.PIN_GROUP, "HELPFUL", opts(AuraRow.PIN_FRAMES, pinned)) or nil
  if not pcall(function() c:SetEnabled(true); c:Show() end) then
    c:Hide()
    return nil
  end
  -- Buttons the container built before the hook was known (none expected,
  -- belt and braces): style them too.
  AuraRow.EachButton(c, function(b) AuraRow.Style(b, size) end)
  return c
end
