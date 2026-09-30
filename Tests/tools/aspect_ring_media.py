"""Generate the aspect ring's two textures (UI/Frame_AspectRing.lua, style B).

Media/AspectRingDisc.tga   150x150: the dark disc (denser inside the tile
                           track), a faint track line through the tile
                           centres, a 1 px black rim and the centre cap.
Media/AspectRingWedge.tga  150x150: a white 60-degree annular slice pointing
                           straight up; the view rotates it toward the pick
                           and tints it with the active colour.
Media/TrackingWheelDisc.tga   178x178: the same disc for the eight-slot
                           tracking wheel (UI/Frame_TrackingWheel.lua), whose
                           tiles sit on radius 59.
Media/TrackingWheelWedge.tga  178x178: the same slice at 45 degrees.

Non-power-of-two on purpose: the client mip-blurs power-of-two textures even
at 1:1 (project rule on pixel art). Drawn 1:1 in UI units; the sizes are
Nock.AspectRingGeometry's (disc = 2 * (ring radius + 30)). Edges are
anti-aliased by 4x supersampling.

Run from the repo root:  python Tests/tools/aspect_ring_media.py
"""
import math
import os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.abspath(os.path.join(HERE, "..", ".."))
MEDIA = os.path.join(ADDON, "Media")

SS = 4                      # supersampling factor
DISC_MARGIN = 30            # the disc's rim beyond the tile centres
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


def disc_sampler(r_track):
    """The disc for tiles centred on r_track (the ring radius)."""
    r_disc = r_track + DISC_MARGIN
    r_inner = r_disc * 0.52          # denser core (the mockup's step)

    def disc_sample(x, y):
        d = math.hypot(x - r_disc, y - r_disc)
        px = (0, 0, 0, 0)
        if d <= r_disc:
            px = DISC_CORE if d <= r_inner else DISC_OUTER
            if abs(d - r_track) <= 0.5:
                px = over(px, TRACK)
            if d >= r_disc - 1:
                px = over(px, RIM)
            if d <= R_CAP:
                px = CAP
        return px
    return disc_sample


def wedge_sampler(r_track, half):
    """A slice of half-angle `half` on the disc for r_track."""
    r_disc = r_track + DISC_MARGIN

    def wedge_sample(x, y):
        dx, dy = x - r_disc, r_disc - y  # image y runs down; up is +dy
        d = math.hypot(dx, dy)
        if d < R_WEDGE_IN or d > r_disc - 1:
            return (255, 255, 255, 0)
        a = math.atan2(dx, dy)           # 0 = up
        return (255, 255, 255, 255) if abs(a) <= half else (255, 255, 255, 0)
    return wedge_sample


def render(sample, name, r_track):
    SIZE = 2 * (r_track + DISC_MARGIN)
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


import sys
only = sys.argv[1:]
R_SIX, R_EIGHT = 45, 59      # Nock.AspectRingGeometry(6) / (8)
for name, sampler, r_track in (
        ("AspectRingDisc.tga", disc_sampler(R_SIX), R_SIX),
        ("AspectRingWedge.tga", wedge_sampler(R_SIX, HALF_WEDGE), R_SIX),
        ("TrackingWheelDisc.tga", disc_sampler(R_EIGHT), R_EIGHT),
        ("TrackingWheelWedge.tga", wedge_sampler(R_EIGHT, math.radians(22.5)), R_EIGHT)):
    if not only or name in only:
        render(sampler, name, r_track)
