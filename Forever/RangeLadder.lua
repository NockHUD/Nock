-- Forever/RangeLadder.lua
-- The Forever range ladder, pure: segment layout, readings -> segment, settle, zone.

-- Evidence: `/nock probe range`, 2026-09-24 (spec 2026-09-24-forever-range-
-- ladder-design.md). Every check below stays plain in combat on a live
-- hostile target; Wing Clip is the true melee edge (8149 reaches a little
-- past it), and the dead zone reaches past CheckInteractDistance 3, so it is
-- "cannot shoot while item 10645 (~20 yd) is in range".
local Ladder = {}

-- TBC block mode's colours (Modules/RangeEngine.lua, not loaded on Forever)
-- plus the React HUD's melee and dead-zone reds.
Ladder.COLORS = {
  melee  = { 0.68, 0.18, 0.20, 1 },
  dead   = { 0.35, 0.10, 0.11, 1 },
  teal   = { 0.11, 0.70, 0.67, 1 },
  blue   = { 0.07, 0.50, 0.73, 1 },
  indigo = { 0.38, 0.40, 0.80, 1 },
  purple = { 0.74, 0.28, 0.75, 1 },
  red    = { 0.86, 0.31, 0.26, 1 },
}
local C = Ladder.COLORS

-- Seconds a new segment must read the same before it is published.
Ladder.SETTLE = 0.15

-- Segment list from Auto Shot's reported range (C_Spell.GetSpellInfo(75):
-- 8/35 without Hawk Eye; +2/4/6 yd per talent rank). `short` is the label
-- drawn inside the segment itself (the ladder has no row of its own under
-- the bar, user 2026-09-24; detailed: the upper bound only, 2026-09-25);
-- `label` is the long name. Every segment has
-- the same width (weight 1, user 2026-09-24).
--
-- `compact` (the default style, user 2026-09-24): five segments, MELEE |
-- DEAD | 8-20 | 20-40 | OUT. The far block (key FAR) lists its brackets in
-- `members` and, lit, shows the live bracket's label and colour. Either way
-- `fine[key]` maps every bracket Resolve can return to its own segment
-- description, so the painter reads the label and colour from it.
function Ladder.Layout(minRange, maxRange, compact)
  local L = Ladder.Detailed(minRange, maxRange)
  if not compact then return L end
  local C2 = {
    L[1], L[2], L[3],
    { key = "FAR", label = "20-" .. (L.has4041 and L.hi or 40), short = "20-" .. (L.has4041 and L.hi or 40),
      weight = 1, color = C.teal, members = {} },
    L[#L],
  }
  for i = 4, #L - 1 do C2[4].members[L[i].key] = true end
  -- Five segments have room for the full text: MELEE, DEAD, 8-20 and the
  -- far block's live bracket keep their wide labels.
  local function ranged(seg)
    local c = {}
    for k, v in pairs(seg) do c[k] = v end
    c.short = seg.wide or seg.short
    return c
  end
  C2[1], C2[2], C2[3] = ranged(L[1]), ranged(L[2]), ranged(L[3])
  local fine = {}
  for k, seg in pairs(L.fine) do fine[k] = ranged(seg) end
  C2.fine, C2.has4041, C2.hi = fine, L.has4041, L.hi
  C2.id = L.id .. "c"
  return C2
end

function Ladder.Detailed(minRange, maxRange)
  local lo = (type(minRange) == "number" and minRange > 0) and math.floor(minRange + 0.5) or 8
  local hi = (type(maxRange) == "number" and maxRange > 0) and math.floor(maxRange + 0.5) or 35
  local far = (hi > 35 and hi < 40) and ("35-" .. hi) or "35-40"
  local L = {
    { key = "MELEE", label = "MELEE",     short = "M", wide = "MELEE", weight = 1, color = C.melee },
    { key = "DEAD",  label = "DEAD ZONE", short = "D", wide = "DEAD",  weight = 1, color = C.dead },
    { key = "8_20",  label = lo .. "-20", short = lo .. "-20", weight = 1, color = C.teal },
    { key = "20_25", label = "20-25",     short = "20-25",   weight = 1, color = C.teal },
    { key = "25_28", label = "25-28",     short = "25-28",   weight = 1, color = C.blue },
    { key = "28_30", label = "28-30",     short = "28-30",   weight = 1, color = C.blue },
    { key = "30_35", label = "30-35",     short = "30-35",   weight = 1, color = C.indigo },
    { key = "35_40", label = far,         short = far,       weight = 1, color = C.purple },
  }
  if hi >= 41 then
    L[#L + 1] = { key = "40_41", label = "40-" .. hi, short = "40-" .. hi, weight = 1, color = C.purple }
  end
  L[#L + 1] = { key = "OOR", label = "OUT OF RANGE", short = "OUT", weight = 1, color = C.red }
  L.id = lo .. "-" .. hi
  L.has4041 = hi >= 41
  L.hi = hi
  L.fine = {}
  -- Nine or ten segments leave no room for "25-28" or "MELEE" inside a
  -- segment: a bracket shows its upper bound only, melee and dead zone a
  -- letter (user 2026-09-25). `wide` keeps the full text for the compact
  -- layout, `label` the long name.
  for i = 1, #L do
    local seg = L[i]
    local upper = seg.short:match("^%d+%-(%d+)$")
    if upper then seg.wide, seg.short = seg.short, upper end
    L.fine[seg.key] = seg
  end
  return L
end

-- One set of readings -> the segment and whether Auto Shot reaches. A nil
-- reading counts as out (the TBC ladder's rule); Wing Clip nil means it is
-- not learned, and then item 8149 decides melee.
function Ladder.Resolve(r, layout)
  local shoot = r.shoot == true
  local melee
  if r.wingClip ~= nil then melee = r.wingClip == true else melee = r.i8149 == true end
  if melee then return "MELEE", shoot end
  -- No item check answered at all (item data not loaded yet after a login):
  -- unknown, never a confident wrong segment.
  if r.i10645 == nil and r.i13289 == nil and r.cid4 == nil and r.i7734 == nil
     and r.i18904 == nil and r.i4945 == nil then
    return nil, shoot
  end
  if r.i10645 == true then
    if shoot then return "8_20", true end
    return "DEAD", false
  end
  if r.i13289 == true then return "20_25", shoot end
  if r.cid4 == true then return "25_28", shoot end
  if r.i7734 == true then return "28_30", shoot end
  if r.i18904 == true then return "30_35", shoot end
  if r.i4945 == true then return "35_40", shoot end
  if shoot then
    if layout and layout.has4041 then return "40_41", true end
    return "35_40", true
  end
  return "OOR", false
end

-- The published segment changes only after the new one has read the same
-- for `hold` seconds; the first segment after no target publishes at once.
-- `st` is the caller's table (no allocation here).
function Ladder.Settle(st, key, shoot, now, hold)
  hold = hold or Ladder.SETTLE
  shoot = shoot and true or false
  if key == nil then
    st.key, st.shoot, st.cKey, st.cShoot, st.since = nil, false, nil, false, nil
    return nil, false
  end
  if st.key == nil or (key == st.key and shoot == st.shoot) then
    st.key, st.shoot, st.cKey, st.since = key, shoot, nil, nil
    return key, shoot
  end
  if key ~= st.cKey or shoot ~= st.cShoot then
    st.cKey, st.cShoot, st.since = key, shoot, now
  end
  if now - st.since >= hold - 1e-9 then
    st.key, st.shoot, st.cKey, st.since = key, shoot, nil, nil
  end
  return st.key, st.shoot
end

-- The zone every other Forever consumer reads (state.target.rangeState) and
-- the matching rangeProg (Nock.RangeFinderClassify's values).
function Ladder.Zone(key, shoot)
  if key == nil then return nil, -1 end
  if key == "MELEE" then return "MELEE", 0.5 end
  if key == "DEAD" then return "CLOSE", 0 end
  if shoot then return "SWEET", -0.5 end
  return "LONG", -1
end

-- A lit segment's colour: the far segment turns red once Auto Shot no
-- longer reaches (Hawk Eye rank 1/2 past 37/39 yd, no talent past 35).
function Ladder.SegColor(seg, shoot)
  if seg.key == "35_40" and not shoot then return C.red end
  return seg.color
end

local LS = rawget(_G, "LibStub")
local Nock = LS and LS("AceAddon-3.0", true) and LS("AceAddon-3.0"):GetAddon("Nock", true)
if Nock then Nock.RangeLadder = Ladder end
return Ladder
