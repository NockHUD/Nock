#!/usr/bin/env python3
"""Generate Media/NockTrackMark-<type>[-back].ttf: the fonts that turn a
creature type NAME into a wrong-tracking warning square.

On WoW Forever the target's creature type is a secret inside an instance:
Lua may not compare it, but FontString:SetText renders it. Each of these
fonts draws NOTHING for every character except the marker of ONE creature
type, which draws a whole picture at the pen position -- a warning square
like the others on the row: the front font (amber) draws the border ring,
the type's initial inside and the word as the label beneath; the back font
(dark) draws the square's fill. Two FontStrings on the same secret text,
one per font, make the two-colour square.

  beasts      'B'    humanoids  'H'    elementals 'E'    giants 'G'
  undead      'U'    demons     'e'    dragonkin  'r'

"Demon" and "Dragonkin" share their initial, so in EVERY font 'D' draws
nothing and advances SHIFT units (3.2 em). The demons and dragonkin
FontStrings sit SHIFT to the LEFT of their clip window, so the second
letter's picture is in view only after a D and stays clipped in "Beast",
"Critter", "Mechanical"... (every picture is drawn at the pen: no negative
bearings, which some renderers drop). English names only (a letter table
per locale is the extension point).

Geometry: the whole picture -- square and label -- sits inside ONE em, the
line box the client is known to lay out as declared (ascent 880, descent
-120, seen with the first pill; a taller line was drawn 0.4 em too high,
2026-09-30). The square is SQUARE units tall, so the font is used at
1000/SQUARE times the square's pixel size; it spans x MARGIN..MARGIN+SQUARE
and hangs from the ascent; the label sits under it, centred, and may be
wider than the square, hence the margin either side. Forever/Spells.lua
carries the same numbers in em (TRACK_MARK_*).

Outlines come from Media/SairaExtraCondensed-Bold.ttf (SIL OFL 1.1; the
derived family carries a new name, as the licence asks). A glyph with NO
outline makes the client draw its missing-glyph box (seen in-game
2026-09-30), so every blank glyph is a 1-unit speck on the baseline.

Run from the repo root:  python Tests/tools/track_mark_font.py
"""
import os
import sys

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SOURCE = os.path.join(ROOT, "Media", "SairaExtraCondensed-Bold.ttf")
OUT_DIR = os.path.join(ROOT, "Media")
FAMILY = "Nock Track Mark"

UPM = 1000
ASCENT, DESCENT = 880, -120         # the line box the client lays out as declared
SQUARE = 650                        # the square's side; the font is used at 1000/SQUARE x the square's pixels
MARGIN = 600                        # room either side for the label, wider than the square (TRACK ELEMENTALS)
LABEL_PREFIX = "TRACK "
SQUARE_TOP = ASCENT                 # the square hangs from the ascent
LABEL_GAP = 148                     # square bottom -> label top (10 px at a 44 px square)
LABEL_CAP = 177                     # label cap height (12 px at a 44 px square)
LABEL_GAP_LETTERS = 10
PICTURE_W = SQUARE + 2 * MARGIN     # the clip window's width (1.85 em); every picture fits it (asserted)
SHIFT = 3200                        # 'D' advances this far (Forever/Spells.lua TRACK_MARK_SHIFT = 3.2 em)
assert SHIFT > PICTURE_W, "a shifted picture must clear the window"
BLANK_ADVANCE = 1                   # a zero-width string may be culled; 1 unit is invisible
STROKE = 44                         # the border ring (3 px at a 44 px square, the row's default border)
CORNER = 60
INITIAL_CAP = 364                   # the initial's cap height inside the square
FILL_INSET = STROKE // 2            # the back fill runs under half the ring: no seam
assert SQUARE_TOP - SQUARE - LABEL_GAP - LABEL_CAP >= DESCENT, "the label's floor is under the line"

# type -> (marker character, word)
MARKS = {
    "beasts":     ("B", "BEASTS"),
    "undead":     ("U", "UNDEAD"),
    "humanoids":  ("H", "HUMANOIDS"),
    "elementals": ("E", "ELEMENTALS"),
    "giants":     ("G", "GIANTS"),
    "demons":     ("e", "DEMONS"),
    "dragonkin":  ("r", "DRAGONKIN"),
}
# Every printable ASCII character gets a glyph; anything else falls to the
# (equally blank) .notdef.
CHARS = [chr(c) for c in range(0x20, 0x7F)]


def rounded_rect(pen, x0, y0, x1, y1, r, clockwise):
    """One rounded-rectangle contour; quadratic corners (one off-curve point each)."""
    pts = [
        ((x0 + r, y0), (x0, y0), (x0, y0 + r)),
        ((x0, y1 - r), (x0, y1), (x0 + r, y1)),
        ((x1 - r, y1), (x1, y1), (x1, y1 - r)),
        ((x1, y0 + r), (x1, y0), (x1 - r, y0)),
    ]
    if not clockwise:
        pts = [(c, b, a) for (a, b, c) in reversed(pts)]
    pen.moveTo(pts[0][0])
    for i, (start, ctrl, end) in enumerate(pts):
        if i:
            pen.lineTo(start)
        pen.qCurveTo(ctrl, end)
    pen.closePath()


class Source:
    def __init__(self, font):
        self.cmap = font.getBestCmap()
        self.glyphs = font.getGlyphSet()
        self.hmtx = font["hmtx"]
        self.cap_h = font["OS/2"].sCapHeight

    def width(self, text, cap, gap):
        s = cap / self.cap_h
        w = 0
        for i, ch in enumerate(text):
            w += self.hmtx[self.cmap[ord(ch)]][0] * s + (gap if i else 0)
        return w

    def draw(self, pen, text, cap, gap, x, baseline):
        s = cap / self.cap_h
        for i, ch in enumerate(text):
            g = self.cmap[ord(ch)]
            self.glyphs[g].draw(TransformPen(pen, (s, 0, 0, s, x, baseline)))
            x += self.hmtx[g][0] * s + gap


def build_front(pen, src, word):
    x0, x1 = MARGIN, MARGIN + SQUARE
    y0, y1 = SQUARE_TOP - SQUARE, SQUARE_TOP
    # the border ring
    rounded_rect(pen, x0, y0, x1, y1, CORNER, True)
    rounded_rect(pen, x0 + STROKE, y0 + STROKE, x1 - STROKE, y1 - STROKE, CORNER - STROKE, False)
    # the initial, centred in the square
    initial = word[0]
    w = src.width(initial, INITIAL_CAP, 0)
    src.draw(pen, initial, INITIAL_CAP, 0, x0 + (SQUARE - w) / 2, y0 + (SQUARE - INITIAL_CAP) / 2)
    # the label, "TRACK <type>", centred under the square
    label = LABEL_PREFIX + word
    lw = src.width(label, LABEL_CAP, LABEL_GAP_LETTERS)
    assert lw < PICTURE_W, (label, lw)
    src.draw(pen, label, LABEL_CAP, LABEL_GAP_LETTERS, x0 + (SQUARE - lw) / 2, y0 - LABEL_GAP - LABEL_CAP)


def build_back(pen):
    x0, x1 = MARGIN + FILL_INSET, MARGIN + SQUARE - FILL_INSET
    y0, y1 = SQUARE_TOP - SQUARE + FILL_INSET, SQUARE_TOP - FILL_INSET
    rounded_rect(pen, x0, y0, x1, y1, CORNER - FILL_INSET, True)


def build_font(kind, marker, word, src, layer):
    names = [".notdef", "space"] + ["u%04X" % ord(c) for c in CHARS if c != " "]
    glyph_order = list(dict.fromkeys(names))
    fb = FontBuilder(UPM, isTTF=True)
    fb.setupGlyphOrder(glyph_order)
    cmap = {ord(c): ("space" if c == " " else "u%04X" % ord(c)) for c in CHARS}
    fb.setupCharacterMap(cmap)
    glyphs, metrics = {}, {}
    for g in glyph_order:
        pen = TTGlyphPen(None)
        adv = BLANK_ADVANCE
        if g == cmap.get(ord(marker)):
            if layer == "front":
                build_front(pen, src, word)
            else:
                build_back(pen)
        else:
            pen.moveTo((0, 0)); pen.lineTo((1, 0)); pen.lineTo((1, 1)); pen.lineTo((0, 1))
            pen.closePath()
        if g == cmap[ord("D")]:
            adv = SHIFT
        glyph = pen.glyph()
        glyph.recalcBounds(None)
        glyphs[g] = glyph
        # The left side bearing MUST be the outline's xMin: the head flag says
        # so, and the rasteriser shifts the ink to match -- a 0 here pulled the
        # ring and the fill left by different amounts (in-game 2026-10-01).
        metrics[g] = (adv, glyph.xMin)
    fb.setupGlyf(glyphs)
    fb.setupHorizontalMetrics(metrics)
    fb.setupHorizontalHeader(ascent=ASCENT, descent=DESCENT)
    fb.setupOS2(sTypoAscender=ASCENT, sTypoDescender=DESCENT, sTypoLineGap=0,
                usWinAscent=ASCENT, usWinDescent=-DESCENT, sCapHeight=INITIAL_CAP)
    style = kind.capitalize() + ("" if layer == "front" else " Back")
    fb.setupNameTable({
        "familyName": FAMILY, "styleName": style,
        "uniqueFontIdentifier": "%s %s" % (FAMILY, style),
        "fullName": "%s %s" % (FAMILY, style), "psName": "NockTrackMark-%s" % style.replace(" ", ""),
        "version": "Version 1.1",
        "copyright": "Outlines from Saira Extra Condensed (SIL OFL 1.1); pictures by Nock.",
        "licenseDescription": "SIL Open Font License, Version 1.1",
    })
    fb.setupPost()
    out = os.path.join(OUT_DIR, "NockTrackMark-%s%s.ttf" % (kind, "" if layer == "front" else "-back"))
    fb.save(out)
    return out


def main():
    src = Source(TTFont(SOURCE))
    for kind, (marker, word) in MARKS.items():
        for layer in ("front", "back"):
            out = build_font(kind, marker, word, src, layer)
            print(os.path.relpath(out, ROOT), os.path.getsize(out), "bytes")
    line_top = ASCENT   # the line box runs from the ascent down to the descent
    print("font scale %.4f x square px; window %.3f em; margin %.3f em; square top %.3f em under the line top; shift %.3f em"
          % (UPM / SQUARE, PICTURE_W / UPM, MARGIN / UPM, (line_top - SQUARE_TOP) / UPM, SHIFT / UPM))
    return 0


if __name__ == "__main__":
    sys.exit(main())
