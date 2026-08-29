-- UI/Frame_ManaBar.lua
-- Thin player-mana bar that sits directly above the range finder. Pure view:
-- data is already produced by the central tick (state.player.mana*); this just
-- maps it to a fill width + optional centered label. Disable/style via options.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local ManaBarView = Nock:NewModule("ManaBarView", "AceEvent-3.0")
local C = Nock.Constants

local function profile(key, fallback)
  local p = Nock.db and Nock.db.profile and Nock.db.profile[key]
  if p ~= nil then return p end
  return fallback
end

local function manaColor()
  local c = profile("manaBarColor", nil)
  if type(c) == "table" and #c >= 3 then return c end
  return C.COLORS.MANA
end

local function manaBarH()
  return profile("manaBarHeight", C.DIM.MANA_BAR_H)
end

function ManaBarView:OnInitialize()
  local parent   = Nock.parentFrame
  local h        = manaBarH()
  -- Full inner width so it lines up with the range finder / other rows.
  local barWidth = C.DIM.HUD_WIDTH - 2 * C.DIM.OUTER_PAD

  local container = CreateFrame("Frame", "NockManaBarRow", parent)
  container:SetSize(barWidth, h)

  local bar = Nock.UI.CreateBar(container, "NockManaBar", barWidth, h, manaColor(), nil, "manaTrack")
  bar:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
  Nock.UI.SetBarFill(bar, 1)

  self.bar   = bar
  self.frame = container
  self._lastRatio = nil
  self._lastMode  = nil
  self._lastCur   = nil
  self._lastMax   = nil
  self._lastPct   = nil

  self:RegisterMessage("NOCK_VISUALS_CHANGED", "ApplyStyle")
end

-- Re-read color + height (HUD.LayoutChildren handles the row spacing via the
-- same manaBarHeight value, so we only resize our own frames here) and force a
-- repaint by invalidating the diff caches.
function ManaBarView:ApplyStyle()
  local bar = self.bar
  if not bar then return end
  local h = manaBarH()
  self.frame:SetHeight(h)
  bar:SetHeight(h)
  bar.fill:SetVertexColor(unpack(manaColor()))
  self._lastRatio = nil
  self._lastMode  = nil   -- force the label to repaint next Refresh
end

-- Text formatting lives in Nock.UI.FormatManaText (Widgets.lua) — shared with
-- the React mana bar, which drives it from its own reactManaText key.

function ManaBarView:Refresh(state)
  local bar = self.bar
  if not bar then return end
  local pl  = state.player or {}
  local pct = pl.manaPct or 100
  local cur = pl.manaCur or 0
  local max = pl.manaMax or 0

  local ratio = pct / 100
  if ratio < 0 then ratio = 0 elseif ratio > 1 then ratio = 1 end
  if not self._lastRatio or math.abs(self._lastRatio - ratio) > 0.005 then
    Nock.UI.SetBarFill(bar, ratio)
    self._lastRatio = ratio
  end

  -- Diff on the integer values; only run string.format when a displayed
  -- number (or the text mode) actually changes — no per-tick allocation
  -- while mana is static (perf rule).
  local mode = profile("manaBarText", "percent")
  local iCur = math.floor(cur + 0.5)
  local iPct = math.floor(pct + 0.5)
  if mode ~= self._lastMode or iCur ~= self._lastCur
     or max ~= self._lastMax or iPct ~= self._lastPct then
    bar.text:SetText(Nock.UI.FormatManaText(mode, iCur, max, iPct))
    self._lastMode, self._lastCur, self._lastMax, self._lastPct = mode, iCur, max, iPct
  end
end
