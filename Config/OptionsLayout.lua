-- Config/OptionsLayout.lua
-- Applies the design canvas' per-tab layout (Config/OptionsLayoutData.lua) onto the built options table: header cards, row order, renames, one-liners, and the walker's side-table metadata.
local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local L = {}
Nock.OptionsLayout = L

-- Listed rows sort under their card at CARD_BASE + i * CARD_STEP + j; anything
-- the layout does not mention trails in a card named after the tab.
local CARD_BASE, CARD_STEP, TRAIL_BASE = 1000, 1000, 90000

local function nodeAt(root, path)
  local node = root
  for seg in path:gmatch("[^%.]+") do
    node = node.args and node.args[seg]
    if type(node) ~= "table" then return nil end
  end
  return node
end

local function setMeta(W, node, key, value)
  if value ~= nil then W.SetMeta(node, key, value) end
end

local function applyTab(W, node, tab)
  local cardKeys, listed = {}, {}
  for i, card in ipairs(tab.cards) do
    local o = CARD_BASE + i * CARD_STEP
    local hdr = node.args[card.key]
    if not hdr then hdr = { type = "header" }; node.args[card.key] = hdr end
    hdr.type, hdr.name, hdr.order, hdr.desc, hdr.hidden = "header", card.name, o, card.desc, nil
    cardKeys[card.key] = true
    setMeta(W, hdr, "icon", card.icon)
    setMeta(W, hdr, "actions", card.actions)
    setMeta(W, hdr, "table", card.table)
    setMeta(W, hdr, "form", card.form)
    setMeta(W, hdr, "stack", card.stack)
    setMeta(W, hdr, "segments", card.segments)
    setMeta(W, hdr, "advanced", card.advanced)
    local j = 0
    for _, key in ipairs(card.rows) do
      local prefix = key:match("^(.-)%*$")
      if prefix then
        local hits = {}
        for k, v in pairs(node.args) do
          if type(k) == "string" and k:sub(1, #prefix) == prefix and type(v) == "table" and v.type then hits[#hits + 1] = { k = k, o = type(v.order) == "number" and v.order or 100 } end
        end
        table.sort(hits, function(a, b) if a.o == b.o then return a.k < b.k end return a.o < b.o end)
        for _, h in ipairs(hits) do j = j + 1; node.args[h.k].order = o + j; listed[h.k] = true end
      else
        local r = node.args[key]
        if type(r) == "table" and r.type then j = j + 1; r.order = o + j; listed[key] = true end
      end
    end
  end
  if tab.rename then
    for k, v in pairs(tab.rename) do
      local r = node.args[k]
      if type(r) == "table" and type(r.name) == "string" then r.name = v end
    end
  end
  if tab.desc then
    for k, v in pairs(tab.desc) do
      local r = node.args[k]
      if type(r) == "table" and r.type then r.desc = (v ~= "" and v) or nil end
    end
  end
  -- Old headers split cards in the wrong places; unlisted descriptions were
  -- folded into the cards' one-liners; unlisted controls trail the layout.
  local trailing = false
  for k, v in pairs(node.args) do
    if type(v) == "table" and v.type and not cardKeys[k] and not listed[k] then
      if v.type == "header" then v.hidden = true
      elseif v.type == "description" then v.hidden = true
      elseif v.type ~= "group" then
        local o = type(v.order) == "number" and v.order or 100
        if o < TRAIL_BASE then v.order = TRAIL_BASE + o end
        trailing = true
      end
    end
  end
  if trailing then
    local hdr = node.args.__trailCard
    if not hdr then hdr = { type = "header" }; node.args.__trailCard = hdr end
    local okn, name = pcall(function() return type(node.name) == "string" and node.name or "More" end)
    hdr.name, hdr.order, hdr.hidden = (okn and W.Strip(name)) or "More", TRAIL_BASE - 1, nil
  elseif node.args.__trailCard then
    node.args.__trailCard.hidden = true
  end
end

-- Tag the built table. Idempotent; RebuildOptionsArgs calls it again after
-- refilling the dynamic blocks.
function L.Apply(root)
  local W, D = Nock.OptionsWalk, Nock.OptionsLayoutData
  if not (W and D) then return end
  local chips, segmented = {}, {}
  for _, k in ipairs(D.CHIPS or {}) do chips[k] = true end
  for _, k in ipairs(D.SEGMENTED or {}) do segmented[k] = true end
  local function walk(node)
    for k, v in pairs(node.args or {}) do
      if type(v) == "table" and v.type then
        if v.type == "group" then walk(v)
        else
          if D.GLOBAL_RENAME[k] and type(v.name) == "string" then v.name = D.GLOBAL_RENAME[k] end
          if chips[k] and v.type == "input" then W.SetMeta(v, "chips", true) end
          if segmented[k] and v.type == "select" then W.SetMeta(v, "segmented", true) end
        end
      end
    end
  end
  walk(root)
  for path, name in pairs(D.PATH_RENAME or {}) do
    local r = nodeAt(root, path)
    if type(r) == "table" and type(r.name) == "string" then r.name = name end
  end
  for _, tab in ipairs(D.TABS) do
    local node = nodeAt(root, tab.path)
    if node and node.args then applyTab(W, node, tab) end
  end
end

-- The layout tabs whose path does not resolve (for the tests and /nock diag).
function L.Missing(root)
  local D, out = Nock.OptionsLayoutData, {}
  for _, tab in ipairs(D and D.TABS or {}) do
    local node = nodeAt(root, tab.path)
    if not node then out[#out + 1] = tab.path
    else
      for _, card in ipairs(tab.cards) do
        for _, key in ipairs(card.rows) do
          if not (node.args and node.args[key]) then out[#out + 1] = tab.path .. "." .. key end
        end
      end
    end
  end
  return out
end

return L
