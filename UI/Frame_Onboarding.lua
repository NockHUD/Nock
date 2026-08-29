-- UI/Frame_Onboarding.lua
-- The setup wizard window: one page at a time, drawn from the page script in
-- Modules/Onboarding.lua. Deliberately sits high on the screen so the HUD it is
-- describing stays visible underneath.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local View = Nock:NewModule("OnboardingView", "AceEvent-3.0")
local C = Nock.Constants

local SOLID_TEX   = "Interface\\Buttons\\WHITE8X8"
local HEADER_FONT = "Numen"

local PANEL_W     = 470
local PANEL_H     = 430
local OUTER       = 16
local BODY_TOP    = 96      -- below eyebrow + title + blurb
local BODY_BOTTOM = 74      -- above the footer
local CARD_H      = 54
local TOGGLE_H    = 40      -- minimum; a row grows to fit a wrapped description
local TOGGLE_TEXT_X   = 26  -- checkbox width + gap: where label and desc start
local TOGGLE_TEXT_TOP = 5   -- checkbox inset + the label's own offset
local TOGGLE_PAD      = 9   -- breathing room under the description
local CHECK_H     = 62      -- name + detail + a line for the fix buttons
local CHECK_ROW_TEXT_H = 38 -- where the fix-button line starts inside a check row
local RECAP_H     = 24
local GAP         = 6
local DOT_W       = 7
local DOT_GAP     = 6

local COL_TITLE  = { 1.00, 0.82, 0.00 }   -- the gold Nock uses for headers
local COL_TEXT   = { 0.95, 0.95, 0.95 }
local COL_DIM    = { 0.66, 0.68, 0.72 }
local COL_FAINT  = { 0.42, 0.45, 0.50 }
local COL_REC    = C.COLORS.NEXT_HIGHLIGHT
local COL_SEL    = C.COLORS.PROC_GLOW
local COL_OK     = C.COLORS.NEXT_HIGHLIGHT
local COL_BAD    = C.COLORS.WARN_RED
local COL_LINE   = { 0.14, 0.16, 0.20, 1 }
local COL_CARD   = { 1, 1, 1, 0.04 }
local COL_BORDER = { 0.20, 0.22, 0.27, 1 }

local function engine()
  return Nock:GetModule("Onboarding", true)
end

-- Deliberately NOT registered with Nock.UI.RegisterFontString: that pool exists
-- to re-apply one of the two HUD sizes on a media refresh, and the wizard fires
-- a visuals refresh on every click. Registering would flatten this window's
-- whole type scale to the overlay size the moment the user picks anything.
local function fs(parent, size, style, color)
  local t = parent:CreateFontString(nil, "OVERLAY")
  t:SetFont(Nock.UI.GetFont() or C.FONT.PATH, size, style or "OUTLINE")
  t:SetTextColor(unpack(color or COL_TEXT))
  return t
end

-- UIPanelButtonTemplate with Nock's font, since the Blizzard default clashes
-- with everything else in the window.
local function button(parent, w, h, text, size)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w, h)
  b:SetText(text)
  if b.GetFontString and b:GetFontString() then
    b:GetFontString():SetFont(Nock.UI.GetFont(), size or 11, "OUTLINE")
  end
  return b
end

--------------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------------
function View:EnsureFrame()
  if self.frame then return self.frame end

  local f = CreateFrame("Frame", "NockOnboarding", UIParent, "BackdropTemplate")
  f:SetSize(PANEL_W, PANEL_H)
  -- High on the screen: the HUD sits at CENTER,-150 by default and the whole
  -- point of the wizard is watching the HUD react.
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 170)
  f:SetFrameStrata("DIALOG")
  Nock.UI.ApplyBackdrop(f, { 0.03, 0.04, 0.05, 0.96 }, COL_BORDER)
  f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:Hide()
  f:SetScript("OnHide", function()
    local e = engine()
    if e then e:Teardown() end
  end)
  -- Esc closes it. The frame is insecure, so this is safe.
  tinsert(UISpecialFrames, "NockOnboarding")

  local close = CreateFrame("Button", nil, f)
  close:SetSize(20, 20)
  close:SetPoint("TOPRIGHT", -6, -6)
  local x = fs(close, 13, "OUTLINE", COL_FAINT)
  x:SetPoint("CENTER")
  x:SetText("x")
  close:SetScript("OnEnter", function() x:SetTextColor(unpack(COL_TEXT)) end)
  close:SetScript("OnLeave", function() x:SetTextColor(unpack(COL_FAINT)) end)
  close:SetScript("OnClick", function() View:Hide() end)

  f.eyebrow = fs(f, 9, "OUTLINE", COL_FAINT)
  f.eyebrow:SetPoint("TOPLEFT", OUTER, -OUTER)

  f.title = f:CreateFontString(nil, "OVERLAY")
  Nock.UI.RegisterHeaderFontString(f.title, HEADER_FONT, 20, "OUTLINE")
  f.title:SetPoint("TOPLEFT", OUTER, -OUTER - 14)
  f.title:SetJustifyH("LEFT")
  f.title:SetTextColor(unpack(COL_TITLE))

  f.blurb = fs(f, 11, nil, COL_DIM)
  f.blurb:SetPoint("TOPLEFT", OUTER, -OUTER - 42)
  f.blurb:SetPoint("RIGHT", f, "RIGHT", -OUTER, 0)
  f.blurb:SetJustifyH("LEFT")
  f.blurb:SetHeight(32)

  -- Body host: every renderer anchors its rows to this.
  local body = CreateFrame("Frame", nil, f)
  body:SetPoint("TOPLEFT", OUTER, -BODY_TOP)
  body:SetPoint("BOTTOMRIGHT", -OUTER, BODY_BOTTOM)
  f.body = body

  f.footnote = fs(f, 10, nil, COL_FAINT)
  f.footnote:SetPoint("BOTTOMLEFT", OUTER, BODY_BOTTOM - 12)
  f.footnote:SetPoint("RIGHT", f, "RIGHT", -OUTER, 0)
  f.footnote:SetJustifyH("LEFT")

  local sep = f:CreateTexture(nil, "ARTWORK")
  sep:SetTexture(SOLID_TEX)
  sep:SetVertexColor(unpack(COL_LINE))
  sep:SetHeight(1)
  sep:SetPoint("BOTTOMLEFT", OUTER, BODY_BOTTOM - 18)
  sep:SetPoint("BOTTOMRIGHT", -OUTER, BODY_BOTTOM - 18)

  -- Progress: dots plus the plain count, because "how much is left" is the
  -- question dots alone never quite answer. One texture per page in the script;
  -- Render shows and re-centres only the ones this run will actually visit,
  -- since the weave macro page appears for weavers only.
  f.dots = {}
  for i = 1, #(engine() and engine().Pages or {}) do
    local d = f:CreateTexture(nil, "ARTWORK")
    d:SetTexture(SOLID_TEX)
    d:SetSize(DOT_W, DOT_W)
    f.dots[i] = d
  end

  f.stepText = fs(f, 10, nil, COL_FAINT)
  f.stepText:SetPoint("BOTTOM", f, "BOTTOM", 0, 32)

  f.settingsBtn = button(f, 92, 18, "All settings", 10)
  f.settingsBtn:SetPoint("BOTTOMRIGHT", -OUTER, 40)
  f.settingsBtn:SetScript("OnClick", function() Nock:OpenConfig() end)

  f.backBtn = button(f, 74, 22, "Back")
  f.backBtn:SetPoint("BOTTOMLEFT", OUTER, 10)
  f.backBtn:SetScript("OnClick", function()
    local e = engine(); if e then e:Back() end
  end)

  f.skipBtn = button(f, 96, 22, "Skip setup")
  f.skipBtn:SetPoint("BOTTOM", f, "BOTTOM", 0, 10)
  f.skipBtn:SetScript("OnClick", function() View:Hide() end)

  f.skipHint = fs(f, 9, nil, COL_FAINT)
  f.skipHint:SetPoint("TOP", f.skipBtn, "BOTTOM", 0, 1)
  f.skipHint:SetText("keeps what you've chosen")

  f.nextBtn = button(f, 90, 22, "Next")
  f.nextBtn:SetPoint("BOTTOMRIGHT", -OUTER, 10)
  f.nextBtn:SetScript("OnClick", function()
    local e = engine(); if e then e:Next() end
  end)

  f.cards, f.toggles, f.checks, f.recaps = {}, {}, {}, {}
  self.frame = f
  return f
end

--------------------------------------------------------------------------------
-- Row pools
--------------------------------------------------------------------------------
-- One pool per row kind. Rows are built once and reused across pages; Render
-- hides the whole pool first, so a page never inherits leftovers.
local function hideAll(pool)
  for _, r in ipairs(pool) do r:Hide() end
end

function View:GetCard(i)
  local f = self.frame
  local card = f.cards[i]
  if card then return card end

  -- A mouse-enabled Frame rather than a Button: only Frame is known to take
  -- BackdropTemplate everywhere in this codebase, and a card needs a backdrop
  -- far more than it needs Button's click machinery.
  card = CreateFrame("Frame", nil, f.body, "BackdropTemplate")
  card:SetHeight(CARD_H)
  card:SetPoint("TOPLEFT", f.body, "TOPLEFT", 0, -(i - 1) * (CARD_H + GAP))
  card:SetPoint("RIGHT", f.body, "RIGHT", 0, 0)
  card:EnableMouse(true)
  Nock.UI.ApplyBackdrop(card, COL_CARD, COL_BORDER)

  local icon = card:CreateTexture(nil, "ARTWORK")
  icon:SetSize(38, 38)
  icon:SetPoint("LEFT", 8, 0)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  card.icon = icon

  card.label = fs(card, 13, "OUTLINE")
  card.label:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -2)
  card.label:SetJustifyH("LEFT")

  card.rec = fs(card, 9, "OUTLINE", COL_REC)
  card.rec:SetPoint("LEFT", card.label, "RIGHT", 6, 0)
  card.rec:SetText("RECOMMENDED")

  card.desc = fs(card, 10, nil, COL_DIM)
  card.desc:SetPoint("TOPLEFT", card.label, "BOTTOMLEFT", 0, -3)
  card.desc:SetPoint("RIGHT", card, "RIGHT", -26, 0)
  card.desc:SetJustifyH("LEFT")

  -- Blizzard's ready-check tick: always on disk, and no font-glyph gamble.
  card.tick = card:CreateTexture(nil, "OVERLAY")
  card.tick:SetSize(16, 16)
  card.tick:SetPoint("RIGHT", -8, 0)
  card.tick:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")

  card:SetScript("OnEnter", function(b)
    if not b._selected then b:SetBackdropBorderColor(0.36, 0.40, 0.48, 1) end
  end)
  card:SetScript("OnLeave", function(b)
    if not b._selected then b:SetBackdropBorderColor(unpack(COL_BORDER)) end
  end)

  f.cards[i] = card
  return card
end

function View:GetToggle(i)
  local f = self.frame
  local row = f.toggles[i]
  if row then return row end

  row = CreateFrame("Button", nil, f.body)
  row:SetHeight(TOGGLE_H)
  row:SetPoint("RIGHT", f.body, "RIGHT", 0, 0)

  local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
  cb:SetSize(22, 22)
  cb:SetPoint("TOPLEFT", 0, -2)
  cb:EnableMouse(false)   -- the whole row is the hit area
  row.check = cb

  row.label = fs(row, 12, "OUTLINE")
  row.label:SetPoint("TOPLEFT", cb, "TOPRIGHT", 4, -3)
  row.label:SetJustifyH("LEFT")

  row.rec = fs(row, 9, "OUTLINE", COL_REC)
  row.rec:SetPoint("LEFT", row.label, "RIGHT", 6, 0)
  row.rec:SetText("RECOMMENDED")

  -- Width is set per render rather than anchored to the row's right edge: the
  -- renderer has to MEASURE the wrapped height to size the row, and an explicit
  -- width is the only way to get a trustworthy GetStringHeight out of a
  -- FontString before the layout pass has run.
  row.desc = fs(row, 10, nil, COL_DIM)
  row.desc:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -2)
  row.desc:SetJustifyH("LEFT")

  f.toggles[i] = row
  return row
end

function View:GetCheck(i)
  local f = self.frame
  local row = f.checks[i]
  if row then return row end

  row = CreateFrame("Frame", nil, f.body)
  row:SetHeight(CHECK_H)
  row:SetPoint("TOPLEFT", f.body, "TOPLEFT", 0, -(i - 1) * (CHECK_H + 2))
  row:SetPoint("RIGHT", f.body, "RIGHT", 0, 0)

  local dot = row:CreateTexture(nil, "ARTWORK")
  dot:SetTexture(SOLID_TEX)
  dot:SetSize(8, 8)
  dot:SetPoint("TOPLEFT", 2, -8)
  row.dot = dot

  row.name = fs(row, 11, "OUTLINE")
  row.name:SetPoint("TOPLEFT", dot, "TOPRIGHT", 8, 3)
  row.name:SetJustifyH("LEFT")

  row.detail = fs(row, 10, nil, COL_DIM)
  row.detail:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
  row.detail:SetPoint("RIGHT", row, "RIGHT", -8, 0)
  row.detail:SetJustifyH("LEFT")

  -- Up to three fix buttons: one "Fix", or the spell-queue value choices. They
  -- sit on their own line because the value labels are long enough to collide
  -- with the detail text otherwise.
  row.btns = {}
  for b = 1, 3 do
    local btn = button(row, 54, 18, "", 10)
    btn:Hide()
    row.btns[b] = btn
  end

  f.checks[i] = row
  return row
end

function View:GetRecap(i)
  local f = self.frame
  local row = f.recaps[i]
  if row then return row end

  row = CreateFrame("Frame", nil, f.body)
  row:SetHeight(RECAP_H)
  row:SetPoint("TOPLEFT", f.body, "TOPLEFT", 0, -(i - 1) * RECAP_H)
  row:SetPoint("RIGHT", f.body, "RIGHT", 0, 0)

  row.key = fs(row, 11, nil, COL_FAINT)
  row.key:SetPoint("LEFT", 4, 0)
  row.key:SetWidth(110)
  row.key:SetJustifyH("LEFT")

  row.val = fs(row, 11, "OUTLINE")
  row.val:SetPoint("LEFT", row.key, "RIGHT", 8, 0)
  row.val:SetJustifyH("LEFT")

  f.recaps[i] = row
  return row
end

--------------------------------------------------------------------------------
-- Renderers
--------------------------------------------------------------------------------
function View:RenderCards(page)
  local e, p = engine(), Nock.db.profile
  -- A card may carry `visible(p)` (the Grounded import): the row is laid out
  -- from the cards that are, and the pool's leftovers hide.
  local shown = {}
  for _, opt in ipairs(page.options or {}) do
    if not (opt.visible and not opt.visible(p)) then shown[#shown + 1] = opt end
  end
  local pool = self.frame and self.frame.cards
  if pool then for k = #shown + 1, #pool do pool[k]:Hide() end end
  for i, opt in ipairs(shown) do
    local card = self:GetCard(i)
    card.icon:SetTexture(opt.icon and opt.icon() or nil)
    card.label:SetText(opt.label)
    card.desc:SetText(opt.desc or "")
    card.rec:SetShown(opt.recommended == true)

    local selected = opt.isSelected and opt.isSelected(p) or false
    card._selected = selected
    card.tick:SetShown(selected)
    if selected then
      card:SetBackdropBorderColor(COL_SEL[1], COL_SEL[2], COL_SEL[3], 1)
      card:SetBackdropColor(COL_SEL[1] * 0.10, COL_SEL[2] * 0.10, COL_SEL[3] * 0.10, 0.28)
    else
      card:SetBackdropBorderColor(unpack(COL_BORDER))
      card:SetBackdropColor(unpack(COL_CARD))
    end

    card:SetScript("OnMouseUp", function()
      if e then e:SelectCard(page, opt); View:Render() end
    end)
    card:Show()
  end
end

function View:RenderToggles(page)
  local e = engine()
  local y = 0
  local bodyW = PANEL_W - OUTER * 2
  for i, opt in ipairs(page.options or {}) do
    local row = self:GetToggle(i)
    local indent = opt.sub and 26 or 0
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", self.frame.body, "TOPLEFT", indent, -y)
    row:SetPoint("RIGHT", self.frame.body, "RIGHT", 0, 0)

    local locked = e and e:IsOptionLocked(opt) or false
    -- Not p[opt.key]: a derived row (the weave macro extras) keeps its state in
    -- the macro text, and the engine is the one that knows how to read it.
    local on = e and e:IsOptionOn(opt) or false
    row.check:SetChecked(on)
    row.label:SetText(opt.label)
    row.desc:SetText(opt.desc or "")

    -- Rows used to advance by a flat TOGGLE_H, which was fine only while every
    -- description happened to fit one line: a description that wrapped ran
    -- straight under the next row's label. Measure the text and grow the row.
    row.desc:SetWidth(bodyW - indent - TOGGLE_TEXT_X)
    local h = TOGGLE_TEXT_TOP + row.label:GetStringHeight() + 2
      + row.desc:GetStringHeight() + TOGGLE_PAD
    if h < TOGGLE_H then h = TOGGLE_H end
    row:SetHeight(h)
    y = y + h + (opt.master and 6 or 0)
    -- One FontString, two badges: the green nudge toward a recommended switch
    -- and the grey caution on a parity feature that shouldn't be the default.
    if opt.recommendOn then
      row.rec:SetText("RECOMMENDED")
      row.rec:SetTextColor(COL_REC[1], COL_REC[2], COL_REC[3])
      row.rec:Show()
    elseif opt.recommendOff then
      row.rec:SetText("NOT RECOMMENDED")
      row.rec:SetTextColor(COL_DIM[1], COL_DIM[2], COL_DIM[3])
      row.rec:Show()
    else
      row.rec:Hide()
    end

    local alpha = locked and 0.4 or 1
    row.label:SetAlpha(alpha); row.desc:SetAlpha(alpha); row.check:SetAlpha(alpha)
    row:SetScript("OnClick", function()
      if locked or not e then return end
      e:ToggleOption(page, opt)
      View:Render()
    end)
    row:Show()
  end
end

function View:RenderChecks(page)
  local sc = Nock:GetModule("SetupCheck", true)
  local i = 0
  for _, check in ipairs(sc and sc.Checks or {}) do
    -- wizardHidden entries are informational and have no fix; they stay in the
    -- settings tree where there is room to explain them. `applies` rows
    -- (the Grounded import) exist only where they apply.
    if not check.wizardHidden and not (check.applies and not check.applies()) then
      i = i + 1
      local row = self:GetCheck(i)
      local ok, value = check.check()
      row.dot:SetVertexColor(unpack(ok and COL_OK or COL_BAD))
      row.name:SetText(check.name)
      row.detail:SetText(
        (check.formatDetail and check.formatDetail(value)) or (ok and "OK" or (check.failHint or ""))
      )
      row.detail:SetTextColor(unpack(ok and COL_FAINT or COL_DIM))

      for _, b in ipairs(row.btns) do b:Hide() end
      if not ok then
        if check.actions then
          -- Laid out left to right on the button line, each sized to its own
          -- label ("400 ms (Blizzard default)" is a lot wider than "100 ms").
          local x = 0
          for bi, action in ipairs(check.actions) do
            local btn = row.btns[bi]
            if btn then
              btn:SetText(action.label)
              btn:SetWidth(math.min(150, 16 + 6 * #action.label))
              btn:ClearAllPoints()
              btn:SetPoint("TOPLEFT", row, "TOPLEFT", x, -CHECK_ROW_TEXT_H)
              x = x + btn:GetWidth() + 4
              if check.actionIsCurrent and check.actionIsCurrent(action) then
                btn:Disable()
              else
                btn:Enable()
              end
              btn:SetScript("OnClick", function()
                if check.applyAction then check.applyAction(action) end
                View:Render()
              end)
              btn:Show()
            end
          end
        elseif check.fix then
          local btn = row.btns[1]
          btn:SetText(check.fixLabel or "Fix")
          btn:SetWidth(math.min(150, 16 + 6 * #(check.fixLabel or "Fix")))
          btn:ClearAllPoints()
          btn:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -CHECK_ROW_TEXT_H)
          btn:Enable()
          btn:SetScript("OnClick", function() check.fix(); View:Render() end)
          btn:Show()
        end
      end
      row:Show()
    end
  end
  local pool = self.frame and self.frame.checks
  if pool then for j = i + 1, #pool do pool[j]:Hide() end end
end

function View:RenderFinish(page)
  local e = engine()
  for i, entry in ipairs(e and e:BuildRecap() or {}) do
    local row = self:GetRecap(i)
    row.key:SetText(entry[1])
    row.val:SetText(entry[2])
    row:Show()
  end

  local f = self.frame
  if not f.finishNote then
    f.finishNote = fs(f.body, 10, nil, COL_DIM)
    f.finishNote:SetPoint("TOPLEFT", f.body, "TOPLEFT", 4, -142)
    f.finishNote:SetPoint("RIGHT", f.body, "RIGHT", 0, 0)
    f.finishNote:SetJustifyH("LEFT")
    f.finishNote:SetText(
      "Everything is unlocked right now so you can drag it into place — closing this window locks all frames. Change anything later, or run this setup again, from the settings window (General tab)."
    )

    f.openBtn = button(f.body, 128, 22, "Open full settings")
    f.openBtn:SetPoint("TOPLEFT", f.body, "TOPLEFT", 0, -186)
    f.openBtn:SetScript("OnClick", function() Nock:OpenConfig() end)

    f.weaveBtn = button(f.body, 128, 22, "Set my weave key")
    f.weaveBtn:SetPoint("LEFT", f.openBtn, "RIGHT", 8, 0)
    f.weaveBtn:SetScript("OnClick", function()
      local dialog = LibStub("AceConfigDialog-3.0", true)
      if not dialog then return end
      dialog:Open("Nock")
      if dialog.SelectGroup then dialog:SelectGroup("Nock", "utilities", "weaveBind") end
    end)
  end
  f.finishNote:Show()
  f.openBtn:Show()
  f.weaveBtn:SetShown(e and e:WantsWeaveKey() or false)
end

--------------------------------------------------------------------------------
-- Render
--------------------------------------------------------------------------------
function View:Render()
  local e = engine()
  if not (e and self.frame) then return end
  local page = e:CurrentPage()
  if not page then return end
  local f = self.frame
  local step, total = e:Progress()
  local last = e:IsLastPage()

  hideAll(f.cards); hideAll(f.toggles); hideAll(f.checks); hideAll(f.recaps)
  if f.finishNote then f.finishNote:Hide(); f.openBtn:Hide(); f.weaveBtn:Hide() end

  f.eyebrow:SetText(page.eyebrow or "")
  f.title:SetText(page.title or "")
  f.blurb:SetText(page.blurb or "")
  f.footnote:SetText(page.footnote or "")

  if page.kind == "cards" then self:RenderCards(page)
  elseif page.kind == "toggles" then self:RenderToggles(page)
  elseif page.kind == "checks" then self:RenderChecks(page)
  elseif page.kind == "finish" then self:RenderFinish(page)
  end

  local rowW = total * DOT_W + (total - 1) * DOT_GAP
  for i, dot in ipairs(f.dots) do
    if i > total then
      dot:Hide()
    else
      dot:ClearAllPoints()
      dot:SetPoint("BOTTOM", f, "BOTTOM", -rowW / 2 + (i - 1) * (DOT_W + DOT_GAP) + DOT_W / 2, 46)
      if i == step then
        dot:SetVertexColor(COL_REC[1], COL_REC[2], COL_REC[3], 1)
      elseif i < step then
        dot:SetVertexColor(COL_REC[1], COL_REC[2], COL_REC[3], 0.45)
      else
        dot:SetVertexColor(0.20, 0.22, 0.26, 1)
      end
      dot:Show()
    end
  end
  f.stepText:SetText(("Step %d of %d"):format(step, total))

  if step > 1 then f.backBtn:Enable() else f.backBtn:Disable() end
  f.nextBtn:SetText(last and "Lock & finish" or "Next")
  f.skipBtn:SetShown(not last)
  f.skipHint:SetShown(not last)
  -- The finish page has its own full-width settings button; two would be noise.
  f.settingsBtn:SetShown(not last)
end

function View:Show()
  self:EnsureFrame()
  self:Render()
  self.frame:Show()
end

function View:Hide()
  if self.frame then self.frame:Hide() end   -- OnHide runs the engine teardown
end
