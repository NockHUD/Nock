-- Tests/settings_pullout_test.lua
-- The settings dropdown list is a scrolling window: clamped offset, opens centred on the current pick, thumb geometry.
-- Run from the repo root: luajit Tests/settings_pullout_test.lua
local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. name) end
end

local _, W = dofile("Tests/lib/options_harness.lua")()
ok(type(W.PullClamp) == "function", "walker exposes the pullout window helpers")

-- clamp: 60 entries, 14 shown -> offsets 0..46
ok(W.PullClamp(-5, 60, 14) == 0, "clamp: never above the top")
ok(W.PullClamp(20, 60, 14) == 20, "clamp: inside the range stays")
ok(W.PullClamp(99, 60, 14) == 46, "clamp: bottom = n - show")
ok(W.PullClamp(3, 10, 14) == 0, "clamp: a short list never scrolls")

-- opening offset: centre the current pick
ok(W.PullOpenOffset(nil, 60, 14) == 0, "open: no current pick -> top")
ok(W.PullOpenOffset(1, 60, 14) == 0, "open: first entry -> top")
ok(W.PullOpenOffset(30, 60, 14) == 22, "open: entry 30 sits mid-window (offset 22)")
ok(W.PullOpenOffset(60, 60, 14) == 46, "open: last entry -> window at the bottom")
ok(W.PullOpenOffset(5, 10, 14) == 0, "open: short list never scrolls")

-- wheel step of 3 rows, as the control applies it
local off = W.PullOpenOffset(1, 60, 14)
off = W.PullClamp(off - (-1) * 3, 60, 14); ok(off == 3, "wheel down moves 3 rows")
off = W.PullClamp(off - (1) * 3, 60, 14);  ok(off == 0, "wheel up moves back")

-- thumb: none for a short list; proportional height, top at offset 0, bottom at the max offset
ok(W.PullThumb(0, 10, 14, 364) == nil, "thumb: short list has none")
local h, y = W.PullThumb(0, 60, 14, 364)
ok(h == math.floor(364 * 14 / 60) and y == 0, "thumb: proportional height, at the top")
local h2, y2 = W.PullThumb(46, 60, 14, 364)
ok(h2 == h and y2 == 364 - h, "thumb: at the bottom when fully scrolled")
local h3 = W.PullThumb(0, 2000, 14, 364)
ok(h3 == 12, "thumb: never thinner than 12 px")

print(("settings_pullout_test: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
