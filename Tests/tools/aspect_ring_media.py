"""Generate the aspect ring's two textures (UI/Frame_AspectRing.lua, style B).

Media/AspectRingDisc.tga   150x150: the dark disc (denser inside the tile
                           track), a faint track line through the tile
                           centres, a 1 px black rim and the centre cap.
Media/AspectRingWedge.tga  150x150: a white 60-degree annular slice pointing
                           straight up; the view rotates it toward the pick
                           and tints it with the active colour.

Non-power-of-two on purpose: the client mip-blurs power-of-two textures even
at 1:1 (project rule on pixel art). Drawn 1:1 at 150 UI units. Edges are
anti-aliased by 4x supersampling.

Run from the repo root:  python Tests/tools/aspect_ring_media.py
"""
import math
import os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.abspath(os.path.join(HERE, "..", ".."))
MEDIA = os.path.join(ADDON, "Media")

SIZE = 150
SS = 4                      # supersampling factor
C = SIZE / 2                # centre, in output pixels
R_DISC = 75                 # disc radius
R_INNER = 39                # denser core (52% of the disc, the mockup's step)
R_TRACK = 45                # tile centres (Nock.AspectRingGeometry ring radius)
R_CAP = 17                  # centre cap
R_WEDGE_IN = 18             # wedge starts just outside the cap
HALF_WEDGE = math.radians(30)

# A solid black disc (user, 2026-09-24: "a full black circle", not see-through).
DISC_CORE = (0, 0, 0, 255)
DISC_OUTER = (0, 0, 0, 255)
RIM = (0, 0, 0, 255)
TRACK = (255, 255, 255, 20)      # rgba 0.08
CAP = RIM                        # the centre cap is the rim's black (user, 2026-09-24)


def over(dst, src):
    """Porter-Duff src over dst, straight alpha, 0..255 ints."""
    sa, da = src[3] / 255.0, dst[3] / 255.0
    oa = sa + da * (1 - sa)
    if oa <= 0:
        return (0, 0, 0, 0)
    rgb = tuple((src[i] * sa + dst[i] * da * (1 - sa)) / oa for i in range(3))
    return (rgb[0], rgb[1], rgb[2], oa * 255)


def disc_sample(x, y):
    d = math.hypot(x - C, y - C)
    px = (0, 0, 0, 0)
    if d <= R_DISC:
        px = DISC_CORE if d <= R_INNER else DISC_OUTER
        if abs(d - R_TRACK) <= 0.5:
            px = over(px, TRACK)
        if d >= R_DISC - 1:
            px = over(px, RIM)
        if d <= R_CAP:
            px = CAP
    return px


def wedge_sample(x, y):
    dx, dy = x - C, C - y            # image y runs down; up is +dy
    d = math.hypot(dx, dy)
    if d < R_WEDGE_IN or d > R_DISC - 1:
        return (255, 255, 255, 0)
    a = math.atan2(dx, dy)           # 0 = up
    return (255, 255, 255, 255) if abs(a) <= HALF_WEDGE else (255, 255, 255, 0)


def render(sample, name):
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    px = img.load()
    n = SS * SS
    for oy in range(SIZE):
        for ox in range(SIZE):
            acc = [0.0, 0.0, 0.0, 0.0]
            for sy in range(SS):
                for sx in range(SS):
                    s = sample(ox + (sx + 0.5) / SS, oy + (sy + 0.5) / SS)
                    a = s[3]
                    acc[0] += s[0] * a
                    acc[1] += s[1] * a
                    acc[2] += s[2] * a
                    acc[3] += a
            if acc[3] > 0:
                rgb = tuple(int(round(acc[i] / acc[3])) for i in range(3))
                px[ox, oy] = (rgb[0], rgb[1], rgb[2], int(round(acc[3] / n)))
    out = os.path.join(MEDIA, name)
    img.save(out, compression=None)
    print("wrote", out, SIZE, "x", SIZE)


render(disc_sample, "AspectRingDisc.tga")
render(wedge_sample, "AspectRingWedge.tga")
