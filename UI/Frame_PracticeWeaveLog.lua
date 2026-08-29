-- UI/Frame_PracticeWeaveLog.lua
-- The weave log: a small skinned panel beside the stage in Focus -- one row per weave of the running fight (the hit's icon, the legs, the re-arm cost, the verdict's icon). Off by default (practiceWeaveLog).

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
local View = Nock:NewModule("PracticeWeaveLogView", "AceEvent-3.0")
local Skin = Nock.Skin

local W = 300
local HEAD_H = 22
local ROW_H = 20
local MAX_ROWS = 8            -- the latest weaves, newest at the top
local PAD = 6
local ICON = 16               -- the spell icon in a row (the client's own art)
-- The number columns, left to right: label over the head, width of the cell.
local COLS = {
  { label = "A-W", w = 44 },
  { label = "W-A", w = 44 },
  { label = "T", w = 50 },
}

-- The verdict a weave row wears, by the grader's own code (T.SEVERITY's
-- vocabulary): the check for a clean one, the triangle for the rest.
local VERDICT_ICON = { good = "check", wait = "check", warn = "warn", bad = "warn" }   -- wait: the paper's own re-arm
local VERDICT_COLOR = { good = "accent", warn = "wait", bad = "bad" }

local function profile(key, fallback)
  local p = Nock.db and Nock.db.profile and Nock.db.profile[key]
  if p ~= nil then return p end
  return fallback
end

local function practice() return Nock:GetModule("Practice", true) end

function View:OnInitialize()
  local f = CreateFrame("Frame", "NockPracticeWeaveLog", UIParent)
  f:SetSize(W, HEAD_H + PAD)
  f:SetFrameStrata("MEDIUM")
  f:SetToplevel(true)
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  Skin.Surface(f, "surface", "line")
  Nock.UI.RegisterPracticeScale(f)
  local pos = profile("practiceWeaveLogPos", nil)
  if pos then f:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
  else f:SetPoint("CENTER", UIParent, "CENTER", 520, 340) end

  -- The head: the title, and the drag handle between fights.
  local head = CreateFrame("Frame", nil, f)
  head:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  head:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
  head:SetHeight(HEAD_H)
  Skin.Surface(head, "surface2")
  local rule = Skin.Rule(head, "lineSoft")
  rule:SetPoint("BOTTOMLEFT", head, "BOTTOMLEFT", 0, 0)
  rule:SetPoint("BOTTOMRIGHT", head, "BOTTOMRIGHT", 0, 0)
  rule:SetHeight(1)
  head:EnableMouse(false)
  head:RegisterForDrag("LeftButton")
  head:SetScript("OnDragStart", function()
    if Nock.state.sim.fightOn then return end
    f:StartMoving()
  end)
  head:SetScript("OnDragStop", function()
    f:StopMovingOrSizing()
    -- Re-anchor to the screen: a drag off a frame-anchored seat keeps the
    -- old anchor otherwise.
    local left, top = f:GetLeft(), f:GetTop()
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    Nock.db.profile.practiceWeaveLogPos = { point = "TOPLEFT", relPoint = "BOTTOMLEFT", x = left, y = top }
    View._anchor = "saved"
  end)
  local title = head:CreateFontString(nil, "OVERLAY")
  Skin.Font(title, "monoMedium", Skin.SIZES.key)
  title:SetPoint("LEFT", head, "LEFT", 8, 0)
  title:SetText("WEAVE LOG")
  Skin.Text(title, "ink3")
  -- The column captions: one FontString per column, at the column's own
  -- left edge and width, right-justified like the numbers under it.
  local x = 8 + 18 + 2 + 40 + 4 + ICON
  for _, c in ipairs(COLS) do
    local cap = head:CreateFontString(nil, "OVERLAY")
    Skin.Font(cap, "mono", 9)
    cap:SetPoint("LEFT", head, "LEFT", x + 6, 0)
    cap:SetWidth(c.w)
    cap:SetJustifyH("RIGHT")
    cap:SetText(c.label)
    Skin.Text(cap, "ink3")
    x = x + 6 + c.w
  end
  self.head = head

  -- The rows, pooled once: #, time, the hit's icon, legs, re-arm, verdict.
  local rows = {}
  for i = 1, MAX_ROWS do
    local r = CreateFrame("Frame", nil, f)
    r:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -(HEAD_H + (i - 1) * ROW_H))
    r:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -(HEAD_H + (i - 1) * ROW_H))
    r:SetHeight(ROW_H)
    if i % 2 == 0 then
      local z = r:CreateTexture(nil, "BACKGROUND")
      z:SetAllPoints(r)
      z:SetColorTexture(1, 1, 1, 0.03)
    end
    local num = r:CreateFontString(nil, "OVERLAY")
    Skin.Font(num, "mono", Skin.SIZES.key)
    num:SetPoint("LEFT", r, "LEFT", 8, 0)
    num:SetWidth(18)
    num:SetJustifyH("LEFT")
    Skin.Text(num, "ink3")
    local at = r:CreateFontString(nil, "OVERLAY")
    Skin.Font(at, "mono", Skin.SIZES.key)
    at:SetPoint("LEFT", num, "RIGHT", 2, 0)
    at:SetWidth(40)
    at:SetJustifyH("LEFT")
    Skin.Text(at, "ink2")
    local ico = r:CreateTexture(nil, "ARTWORK")
    ico:SetSize(ICON, ICON)
    ico:SetPoint("LEFT", at, "RIGHT", 4, 0)
    ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    -- Ishri's three: A-W, W-A, T in ms (T coloured by his steps), then the
    -- re-arm cost when a release paid the retry grid.
    local function col(after, w, color)
      local fs = r:CreateFontString(nil, "OVERLAY")
      Skin.Font(fs, "mono", Skin.SIZES.key)
      fs:SetPoint("LEFT", after, "RIGHT", 6, 0)
      fs:SetWidth(w)
      fs:SetJustifyH("RIGHT")
      fs:SetWordWrap(false)
      Skin.Text(fs, color)
      return fs
    end
    local a2w = col(ico, COLS[1].w, "ink2")
    local w2a = col(a2w, COLS[2].w, "ink2")
    local tot = col(w2a, COLS[3].w, "ink")
    r.a2w, r.w2a, r.tot = a2w, w2a, tot
    -- (The re-arm column, the head's total and the row tooltip went on
    -- 2026-08-27 -- user: the three numbers and the verdict icon are the row.)
    local vico = r:CreateTexture(nil, "OVERLAY")
    vico:SetPoint("RIGHT", r, "RIGHT", -8, 0)
    Skin.Icon(vico, "check", "accent")
    Skin.IconSize(vico)
    r.num, r.at, r.ico, r.vico = num, at, ico, vico
    r:Hide()
    rows[i] = r
  end
  self.rows = rows
  self.frame = f
  self._n, self._sig = 0, nil
  f:Hide()
end

function View:OnEnable()
  self:RegisterMessage("NOCK_PRACTICE_RESET_POS", "ResetPos")
  self:Apply()
end

function View:ResetPos()
  local f = self.frame
  if not f then return end
  Nock.db.profile.practiceWeaveLogPos = nil
  f:ClearAllPoints()
  f:SetPoint("CENTER", UIParent, "CENTER", 520, 340)
end

-- TWO SOURCES, ONE TABLE. In practice the rows come off the engine's stream;
-- out of it, off WeaveBind's live weave-delay entries (Nock.state.weave
-- .entries, the aerthax definitions: ability->weave = the last ranged cast
-- COMPLETES -> the melee event, weave->ability = the melee -> the next
-- ranged cast STARTS, total = the two). Both sources fill the same columns:
--   #  t  [hit]  A-W  W-A  T  (Ishri's thresholds on T)  re-arm  [verdict]
-- The panel shows whenever the flag is on and there is something to show:
-- practice on a weave paper, or a live fight that had a weave.
local T_GOOD, T_OK, T_SLOW = 0.8, 1.0, 1.2      -- Ishri's colour steps on the total
local function totalColor(tot)
  if not tot then return "ink3" end
  if tot < T_GOOD then return "accent" elseif tot < T_OK then return "wait" elseif tot < T_SLOW then return "multi" end
  return "bad"
end

-- TWO FLAGS (user, 2026-08-27: the panel came up in a raid because the
-- practice toolbar's Log button had been left on). `practiceWeaveLog` is the
-- practice panel -- the toolbar's Log, the Focus head's LOG -- and shows only
-- while practice runs on a weave paper. `weaveLogPanel` is the LIVE panel
-- (/nock weavelog panel, Options -> Weave Bind), off by default; nothing
-- appears in a real fight unless it was asked for by name.
function View:WantShown()
  local p = practice()
  if Nock.state.sim.active then
    local weaves = (p and p.PaperWeaves and p:PaperWeaves()) and true or false
    -- Expert mode IS the two panels: on a weave paper the log is up whatever
    -- the toolbar's Log flag says (2026-08-27).
    local wb = Nock:GetModule("PracticeWorkbench", true)
    if wb and wb.IsExpert and wb:IsExpert() then return weaves end
    if not profile("practiceWeaveLog", false) then return false end
    return weaves
  end
  if not profile("weaveLogPanel", false) then return false end
  local w = Nock.state.weave
  return (w and w.entries and #w.entries > 0) and true or false
end

-- The live flag moved (the slash, Options): WeaveBind measures live only
-- while the live panel wants it.
function View:Apply()
  local wb = Nock:GetModule("WeaveBind", true)
  if wb and wb.SetMetrics then wb:SetMetrics(profile("weaveLogPanel", false) and true or false) end
end

function View:Seat()
  if profile("practiceWeaveLogPos", nil) then return end
  local cv = Nock:GetModule("PracticeConveyorView", true)
  local wb = Nock:GetModule("PracticeWorkbench", true)
  local anchor
  if Nock.state.sim.active then
    local cl = Nock:GetModule("PracticeCombatLogView", true)
    if wb and wb.IsExpert and wb:IsExpert() and cl and cl.frame then anchor = cl.frame
    elseif cv and cv.IsFocus and cv:IsFocus() and cv.frame then anchor = cv.frame
    elseif wb and wb.frame then anchor = wb.frame end
  end
  if anchor == self._anchor then return end
  self._anchor = anchor
  local f = self.frame
  f:ClearAllPoints()
  if anchor then f:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 8, 0)
  else f:SetPoint("CENTER", UIParent, "CENTER", 520, 340) end
end

-- The verdict of lane "weave" nearest a weave's end, from the grader.
local function verdictFor(g, t)
  if not (g and g.verdicts) then return nil end
  local best, bestD
  for i = #g.verdicts, 1, -1 do
    local v = g.verdicts[i]
    if v.key == "weave" then
      local d = v.t - t
      if d < 0 then d = -d end
      if d <= 0.6 and (not bestD or d < bestD) then best, bestD = v, d end
      if v.t < t - 1 then break end
    end
  end
  return best
end

-- One row painted from a plain record: { n, t, hit ("r"/"w"), a2w, w2a, total,
-- sev ("good"/"warn"/"bad"/nil) }.
local function paintRow(r, rec)
  r.num:SetText(("%d"):format(rec.n))
  r.at:SetText(("%.1fs"):format(rec.t))
  local tex = rec.hit and Nock.UI.PracticeIconFor(rec.hit == "r" and "r" or "w") or nil
  if tex then r.ico:SetTexture(tex); r.ico:SetDesaturated(rec.hit ~= "r"); r.ico:Show() else r.ico:Hide() end
  -- No hit landed (released before the swing, fired too early, out of reach):
  -- a FAILED weave, said in red rather than three dashes (user, 2026-08-27).
  local failed = rec.hit == nil
  r.a2w:SetText(rec.a2w and ("%.0f"):format(rec.a2w * 1000) or "-")
  r.w2a:SetText(rec.w2a and ("%.0f"):format(rec.w2a * 1000) or "-")
  Skin.Text(r.a2w, failed and "bad" or "ink2")
  Skin.Text(r.w2a, failed and "bad" or "ink2")
  if failed then
    r.tot:SetText("FAILED")
    Skin.Text(r.tot, "bad")
  else
    r.tot:SetText(rec.total and ("%.0f"):format(rec.total * 1000) or "-")
    Skin.Text(r.tot, totalColor(rec.total))
  end
  if rec.sev then
    Skin.Icon(r.vico, VERDICT_ICON[rec.sev] or "warn", VERDICT_COLOR[rec.sev] or "wait")
    Skin.IconSize(r.vico)
    r.vico:Show()
  else
    r.vico:Hide()
  end
  r:Show()
end

-- The practice stream as records: every `weave/done`, its melee hit, the
-- last ranged completion before the hit and the first ranged start after.
local recs = {}

local function practiceRecs(e, g, T, t0)
  local n = e and e.n or 0
  local total = 0
  for i = 1, n do if e.events[i].kind == "weave" and e.events[i].edge == "done" then total = total + 1 end end
  local shown = 0
  for i = n, 1, -1 do
    local ev = e.events[i]
    if ev.kind == "weave" and ev.edge == "done" and ev.legs then
      shown = shown + 1
      if shown > MAX_ROWS then break end
      local L = ev.legs
      local hitAt = L.hitAt
      -- The last ranged completion before the hit, the first start after.
      local lastEnd, nextStart, lastKey, nextKey
      if hitAt then
        for j = i, 1, -1 do
          local o = e.events[j]
          if o.kind == "cast" and not o.cancelled and o.t1 and o.t1 <= hitAt then lastEnd, lastKey = o.t1, o.spell; break end
          if o.kind == "auto" and o.t <= hitAt then lastEnd, lastKey = o.t, "auto"; break end
          if o.kind == "press" and o.key == "arcane" and o.result == "ok" and o.t <= hitAt then lastEnd, lastKey = o.t, "arcane"; break end
        end
        -- The next ranged cast to BEGIN after the hit -- the earliest start,
        -- not the first event filed: the stream files a cast at its END and an
        -- auto at its release, so a Steady that began before the auto's wind-up
        -- is filed after it. Auto Shot counts from its wind-up (SPELL_CAST_START
        -- live), Steady/Multi from the cast start, an instant from the press.
        local j0 = i
        while j0 > 1 and (e.events[j0 - 1].t or 0) >= hitAt do j0 = j0 - 1 end
        for j = j0, n do
          local o = e.events[j]
          if o.t > hitAt + 8 then break end
          local s, k
          if o.kind == "cast" and o.t0 and o.t0 >= hitAt then s, k = o.t0, o.spell
          elseif o.kind == "auto" and o.windupAt and o.windupAt >= hitAt then s, k = o.windupAt, "auto"
          elseif o.kind == "press" and o.result == "ok" and o.key ~= "steady" and o.key ~= "multi" and o.key ~= "autoshot" and o.key ~= "weave" and o.t >= hitAt then s, k = o.t, o.key end
          if s and (not nextStart or s < nextStart) then nextStart, nextKey = s, k end
        end
        -- (The loop below starts BEFORE the done event: an Arcane pressed on
        -- the way out, with the weave key still held, is filed ahead of the
        -- weave's own `done` -- starting at `i` skipped it and the NEXT shot
        -- closed the weave, seconds later. User, 2026-08-27.)
        -- Nothing filed yet: the cast or wind-up RUNNING now already ends the
        -- weave -- the row fills in when the Steady begins, not when it lands
        -- (user, 2026-08-26).
        local c = e.cast
        if c and c.t0 and c.t0 >= hitAt and (not nextStart or c.t0 < nextStart) then nextStart, nextKey = c.t0, c.spell end
        if e.windupAt and e.windupAt >= hitAt and (not nextStart or e.windupAt < nextStart) then nextStart, nextKey = e.windupAt, "auto" end
      end
      local a2w = (hitAt and lastEnd) and (hitAt - lastEnd) or nil
      local w2a = (hitAt and nextStart) and (nextStart - hitAt) or nil
      local tot = (a2w and w2a) and (a2w + w2a) or nil
      local v = verdictFor(g, ev.t)
      local sev = v and T and T.SEVERITY[v.code] or (hitAt and "good" or "bad")
      local rec = recs[shown]
      if not rec then rec = {}; recs[shown] = rec end
      rec.n, rec.t, rec.hit = total - shown + 1, (L.downAt or ev.t) - t0, L.hit
      rec.a2w, rec.w2a, rec.total, rec.sev = a2w, w2a, tot, sev
    end
  end
  return shown, total
end

-- The live entries as records (WeaveBind's, newest last).
local function liveRecs(list, t0)
  local total = #list
  local shown = 0
  for i = total, 1, -1 do
    shown = shown + 1
    if shown > MAX_ROWS then break end
    local en = list[i]
    local rec = recs[shown]
    if not rec then rec = {}; recs[shown] = rec end
    rec.n, rec.t = i, en.t - t0
    rec.hit = (en.name == "Raptor Strike") and "r" or "w"
    rec.a2w, rec.w2a, rec.total, rec.sev = en.a2w, en.w2a, en.total, nil
  end
  return shown, total
end

function View:Refresh(state)
  local f = self.frame
  if not f then return end
  if not self:WantShown() then
    if f:IsShown() then f:Hide() end
    return
  end
  if not f:IsShown() then f:Show() end
  self:Seat()
  local p = practice()
  local T = Nock.PracticeTimeline
  local shown, total, sig
  if state.sim.active then
    local e, g = p and p.engine, p and p.grader
    local n = e and e.n or 0
    local nv = (g and g.verdicts and #g.verdicts) or 0
    sig = n * 7919 + nv
    if sig == self._sig then return end
    self._sig = sig
    shown, total = practiceRecs(e, g, T, state.sim.t0 or 0)
  else
    local w = state.weave
    sig = -((w.entriesN or 0) * 7919 + #(w.entries or {}))
    if sig == self._sig then return end
    self._sig = sig
    shown, total = liveRecs(w.entries or {}, w.combatAt or (w.entries[1] and w.entries[1].t) or 0)
  end
  if shown > MAX_ROWS then shown = MAX_ROWS end
  for i = 1, shown do paintRow(self.rows[i], recs[i]) end
  for i = shown + 1, MAX_ROWS do self.rows[i]:Hide() end
  f:SetHeight(HEAD_H + (shown > 0 and shown or 1) * ROW_H + PAD)
  self.head:EnableMouse(not Nock.state.sim.fightOn)
end
