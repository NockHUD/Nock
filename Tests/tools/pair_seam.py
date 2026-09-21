"""Generate Media/PairSeam.tga: the divider drawn over a glued pair tile.

A 12x24 RGBA strip (non-power-of-two on purpose: the client mip-blurs
power-of-two textures even at 1:1, see the project rule on pixel art). Every
row is identical, so the strip stretches over any tile height exactly. The
column profile is a 2 px near-black line at the centre with a soft shadow
falling off over 5 px on each side, the look of a Fonsas-style dual icon.

Run from the repo root:  python Tests/tools/pair_seam.py
"""
import os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ADDON, "Media", "PairSeam.tga")

W, H = 12, 24
# Alpha per column, symmetric around the seam between columns 5 and 6: a 2 px
# near-black line with a soft shadow on both halves (the user's pick over the
# one-sided drop-shadow variant, 2026-09-21).
PROFILE = [0.00, 0.10, 0.20, 0.32, 0.50, 0.88, 0.88, 0.50, 0.32, 0.20, 0.10, 0.00]
LINE = (6, 6, 8)          # the divider itself: near-black with a hint of blue
SHADOW = (0, 0, 0)        # the fall-off: pure black at lower alpha

img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
px = img.load()
for x in range(W):
    a = PROFILE[x]
    rgb = LINE if x in (5, 6) else SHADOW
    for y in range(H):
        px[x, y] = (rgb[0], rgb[1], rgb[2], int(round(a * 255)))

img.save(OUT, compression=None)
print("wrote", OUT, W, "x", H)
