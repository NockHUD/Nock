-- Tests/pair_seam_test.lua
-- Media/PairSeam.tga (from Tests/tools/pair_seam.py) is the divider over a
-- glued pair tile: present, 32-bit, and NON-power-of-two in both dimensions
-- (a power-of-two texture is mip-blurred by the client even at 1:1).
-- Run from the repo root: luajit Tests/pair_seam_test.lua

local pass, fail = 0, 0
local function ok(cond, name)
  if cond then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. name) end
end

local f = io.open("Media/PairSeam.tga", "rb")
ok(f ~= nil, "Media/PairSeam.tga exists")
if not f then print(("pair_seam: %d passed, %d failed"):format(pass, fail)); os.exit(1) end
local hdr = f:read(18); f:close()
local function u16(s, i) return s:byte(i) + s:byte(i + 1) * 256 end
local imageType = hdr:byte(3)
local w, h, bpp = u16(hdr, 13), u16(hdr, 15), hdr:byte(17)
ok(imageType == 2, "uncompressed true-colour TGA (type 2), got " .. tostring(imageType))
ok(bpp == 32, "32 bits per pixel (alpha), got " .. tostring(bpp))
local function pow2(n) return n > 0 and bit.band(n, n - 1) == 0 end
ok(not pow2(w) and not pow2(h), ("non-power-of-two size, got %dx%d"):format(w, h))
ok(w == 12 and h == 24, ("12x24 strip, got %dx%d"):format(w, h))

-- The view references the shipped path.
local src = io.open("UI/Frame_ReactCooldowns.lua", "rb"):read("*a")
ok(src:find("Media\\\\PairSeam", 1, true) ~= nil, "Frame_ReactCooldowns references Media\\PairSeam")

print(("pair_seam: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
