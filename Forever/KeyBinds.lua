-- Forever/KeyBinds.lua
-- User-made press/release key binds: one key, one macro on the press edge and another on the release edge, so a spell that is not up never blocks the other.

-- Spec: docs/superpowers/specs/2026-11-18-forever-key-binds-design.md.
-- The button recipe is the weave key's (Forever/WeaveKey.lua): a
-- SecureActionButtonTemplate with both click edges, its wrapped OnClick
-- swapping the macrotext and the useOnKeyDown attribute per edge. One button
-- per bind, made on demand and never destroyed; Apply re-fills them from the
-- profile in list order, out of combat only.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local KB = Nock:NewModule("KeyBinds", "AceEvent-3.0")
Nock.KeyBinds = KB

KB.PREFIX = "NockKeyBind"
KB.MAX_BODY = 255
KB.selected = 1   -- the bind the settings page edits (view state)

-- Pure: the profile's list, non-tables dropped; created when missing.
function KB.List(p)
  if type(p.keyBinds) ~= "table" then p.keyBinds = {} end
  local l = p.keyBinds
  for i = #l, 1, -1 do if type(l[i]) ~= "table" then table.remove(l, i) end end
  return l
end

-- Pure: who else holds `key` -- "bind:<name>", "weave key" or nil.
function KB.KeyOwner(list, key, except, weaveKey)
  if type(key) ~= "string" or key == "" then return nil end
  for i, b in ipairs(list) do
    if i ~= except and b.key == key then return "bind:" .. tostring(b.name or ("#" .. i)) end
  end
  if weaveKey == key then return "weave key" end
  return nil
end

-- The lines of a body, trimmed, blanks dropped.
local function lines(text)
  local out = {}
  for line in ((text or "") .. "\n"):gmatch("(.-)\n") do
    line = line:gsub("\r", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" then out[#out + 1] = line end
  end
  return out
end

-- Pure: the first spell (or item) a body casts: /cast or /use, conditions,
-- a leading ! and any later ; clause dropped. nil when it casts nothing.
function KB.FirstSpell(text)
  for _, line in ipairs(lines(text)) do
    local rest = line:match("^/cast%s+(.+)$") or line:match("^/use%s+(.+)$")
    if rest then
      rest = rest:match("^([^;]*)"):gsub("%b[]", ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("^!", "")
      if rest ~= "" then return rest end
    end
  end
  return nil
end

-- The icon for a spell or item name: spell first (C_Spell takes names the
-- player knows), then an item in the bags; nil when neither answers.
function KB.Icon(name)
  local API = Nock.API
  if type(name) ~= "string" or name == "" or not API then return nil end
  if API.SpellInfo then
    local _, icon = API.SpellInfo(name)
    if icon then return icon end
  end
  return API.ItemIconByName and API.ItemIconByName(name) or nil
end

-- The first spell a body casts, else its first line, else "empty".
local function headline(text)
  return KB.FirstSpell(text) or lines(text)[1] or "empty"
end

function KB.Summary(bind)
  return "↓ " .. headline(bind and bind.down) .. "  ↑ " .. headline(bind and bind.up)
end

function KB.New(list)
  list[#list + 1] = { name = "Untitled bind", down = "", up = "" }
  return #list
end

-- A copy right after i; never with the key (two binds never share one).
function KB.Duplicate(list, i)
  local src = list[i]
  if not src then return KB.Clamp(list, i) end
  table.insert(list, i + 1, { name = (src.name or "") .. " copy", down = src.down, up = src.up })
  return i + 1
end

function KB.Remove(list, i)
  if list[i] then table.remove(list, i) end
  return KB.Clamp(list, i)
end

function KB.Clamp(list, i)
  local n = #list
  if n == 0 then return 0 end
  i = tonumber(i) or 1
  if i < 1 then return 1 end
  if i > n then return n end
  return i
end

--------------------------------------------------------------------------------
-- Runtime
--------------------------------------------------------------------------------

local WRAP_ONCLICK = [[
  if down then
    self:SetAttribute("useOnKeyDown", true)
    self:SetAttribute("macrotext", self:GetAttribute("macrotextDown") or "")
  else
    self:SetAttribute("useOnKeyDown", false)
    self:SetAttribute("macrotext", self:GetAttribute("macrotextUp") or "")
  end
]]

local buttons = {}
local function profile() return Nock.db and Nock.db.profile end
local function inCombat() return Nock.Flavor.Plain(_G.InCombatLockdown and _G.InCombatLockdown()) == true end

local function button(i)
  local b = buttons[i]
  if b then return b end
  b = CreateFrame("Button", KB.PREFIX .. i, UIParent, "SecureActionButtonTemplate")
  b:SetAttribute("type", "macro")
  b:RegisterForClicks("AnyDown", "AnyUp")
  SecureHandlerWrapScript(b, "OnClick", b, WRAP_ONCLICK)
  buttons[i] = b
  return b
end

function KB:OnEnable()
  self:RegisterEvent("PLAYER_REGEN_ENABLED")
  self:RegisterMessage("NOCK_KEYBINDS_CHANGED", "Apply")
  -- The core sends this on every profile switch, copy, reset and import.
  self:RegisterMessage("NOCK_WEAVEBIND_CHANGED", "Apply")
  self:Apply()
end

function KB:Pending() return self._pending == true end

function KB:Apply()
  local p = profile()
  if not p then return end
  local list = KB.List(p)
  KB.selected = KB.Clamp(list, KB.selected)
  if inCombat() then self._pending = true; return end
  self._pending = nil
  for _, b in pairs(buttons) do ClearOverrideBindings(b) end
  for i, bind in ipairs(list) do
    local b = button(i)
    b:SetAttribute("macrotextDown", bind.down or "")
    b:SetAttribute("macrotextUp", bind.up or "")
    if type(bind.key) == "string" and bind.key ~= "" then SetOverrideBindingClick(b, true, bind.key, b:GetName()) end
  end
  for i, b in pairs(buttons) do
    if i > #list then b:SetAttribute("macrotextDown", ""); b:SetAttribute("macrotextUp", "") end
  end
end

function KB:PLAYER_REGEN_ENABLED()
  if self._pending then self:Apply() end
end
