-- UI/ReactRangeLadder.lua
-- The Forever Range Finder widget: one segment per distance bracket, each labelled inside itself, the target's lit.

local Nock = LibStub("AceAddon-3.0"):GetAddon("Nock")
Nock.UI = Nock.UI or {}
local RL = {}
Nock.UI.RangeLadder = RL

local WHITE8X8 = "Interface\\Buttons\\WHITE8X8"
RL.OFF = { 0.16, 0.16, 0.16, 1 }   -- an unlit segment (the React strip's off grey)
RL.SEAM = { 0, 0, 0, 1 }           -- the 1 px seam between segments
-- In-segment labels: their own face, not the React HUD font (a display
-- face like LEMON MILK is too wide for the segments). IBM Plex Mono Medium,
-- picked by eye in `/nock probe fonts` (user 2026-09-24); no outline, a drop
-- shadow for the lit colours. Outside the React font roster so the skin
-- pass leaves it.
RL.LABEL_FACE = [[Interface\AddOns\Nock\Media\IBMPlexMono-Medium.ttf]]
RL.LABEL_FONT = 10
RL.LABEL_FLAGS = ""
RL.SHADOW_PX = 1                   -- label drop shadow, in DEVICE pixels (user 2026-09-24)
RL.DIM = 0.3                       -- an unlit segment's label alpha (quieter than the lit one, user 2026-09-24)
RL.MAX_SEGMENTS = 10               -- the Hawk Eye 3 layout (Forever/RangeLadder.lua)

-- Pure: segment offsets and widths across innerW, cut on whole device pixels
-- (`dev` physical px per unit) so every seam lands on one pixel column and
-- the last segment ends exactly at innerW. `out` is reused when given.
function RL.Slices(layout, innerW, dev, out)
  out = out or {}
  dev = (dev and dev > 0) and dev or 1
  local total = 0
  for i = 1, #layout do total = total + layout[i].weight end
  local px = math.floor(innerW * dev + 0.5)
  local acc, prev = 0, 0
  for i = 1, #layout do
    acc = acc + layout[i].weight
    local edge = (i == #layout) and px or math.floor(px * acc / total + 0.5)
    local s = out[i] or {}
    s.x, s.w = prev / dev, (edge - prev) / dev
    out[i] = s
    prev = edge
  end
  for i = #layout + 1, #out do out[i] = nil end
  return out
end

-- The frame is the bar itself (bordered): the segment textures, one label
-- per segment (in RL.LABEL_FACE), all made here. The lit segment is told by
-- its colour and its bright label; there is no underline marker (user,
-- 2026-09-24).
function RL.Create(parent, opts)
  local f = CreateFrame("Frame", "NockReactRangeLadder", parent, "BackdropTemplate")
  Nock.UI.ApplyBackdrop(f, opts.bg, opts.border)
  local seam = f:CreateTexture(nil, "BORDER")
  seam:SetTexture(WHITE8X8)
  seam:SetVertexColor(RL.SEAM[1], RL.SEAM[2], RL.SEAM[3], RL.SEAM[4])
  f.seam = seam
  f.segs, f.labels, f.slices = {}, {}, {}
  for i = 1, RL.MAX_SEGMENTS do
    local t = f:CreateTexture(nil, "ARTWORK")
    t:SetTexture(WHITE8X8)
    t:Hide()
    f.segs[i] = t
    local fs = f:CreateFontString(nil, "OVERLAY")
    -- SafeSetFont: the first FontString on a new face needs the size bounce
    -- opts.face/size/flags override the label font (the font preview probe)
    local face, size, flags = opts.face or RL.LABEL_FACE, opts.size or RL.LABEL_FONT, opts.flags or RL.LABEL_FLAGS
    if Nock.UI.SafeSetFont then Nock.UI.SafeSetFont(fs, face, size, flags)
    else fs:SetFont(face, size, flags) end
    fs:Hide()
    f.labels[i] = fs
  end
  return f
end

-- Place everything for `layout` at width w and bar height hBar; showAll =
-- every segment labelled (off: only the lit one). `e` = the 1 device px
-- edge in units. Layout time only.
function RL.Layout(f, layout, w, hBar, showAll, dev, e)
  e = e or 1
  f.layout, f.showAll = layout, showAll and true or false
  f.innerW, f.e = w - 2 * e, e
  f.seam:ClearAllPoints()
  f.seam:SetPoint("TOPLEFT", f, "TOPLEFT", e, -e)
  f.seam:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -e, e)
  local slices = RL.Slices(layout, f.innerW, dev, f.slices)
  local shadow = RL.SHADOW_PX / ((dev and dev > 0) and dev or 1)
  local n = #layout
  for i = 1, n do
    local t, s = f.segs[i], slices[i]
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", f, "TOPLEFT", e + s.x, -e)
    -- every segment but the last leaves one device px of seam on its right
    t:SetSize(math.max(e, s.w - ((i < n) and e or 0)), math.max(e, hBar - 2 * e))
    t:SetVertexColor(RL.OFF[1], RL.OFF[2], RL.OFF[3], RL.OFF[4])
    t:Show()
    local fs = f.labels[i]
    fs:SetText(layout[i].short)
    -- drop shadow in device pixels, re-set every layout (a SetFont clears it)
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetShadowOffset(shadow, -shadow)
    fs:ClearAllPoints()
    fs:SetPoint("CENTER", t, "CENTER", 0, 0)
  end
  for i = n + 1, RL.MAX_SEGMENTS do f.segs[i]:Hide(); f.labels[i]:Hide() end
  f._key, f._shoot = false, nil   -- force the next Paint
end

-- Light `key`'s segment (nil = none). Diffed: repaints only on a change.
function RL.Paint(f, key, shoot)
  shoot = shoot and true or false
  if key == f._key and shoot == f._shoot then return end
  f._key, f._shoot = key, shoot
  local layout = f.layout
  if not layout then return end
  for i = 1, #layout do
    local seg = layout[i]
    -- the compact far block lights for any of its brackets and then reads
    -- as that bracket: its colour, its label
    local on = seg.key == key or (seg.members ~= nil and key ~= nil and seg.members[key] == true)
    local live = (on and seg.members and layout.fine and layout.fine[key]) or seg
    local c = on and Nock.RangeLadder.SegColor(live, shoot) or RL.OFF
    f.segs[i]:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
    local fs = f.labels[i]
    if seg.members then fs:SetText(live.short) end
    fs:SetTextColor(1, 1, 1, on and 1 or RL.DIM)
    if on or f.showAll then fs:Show() else fs:Hide() end
  end
end
