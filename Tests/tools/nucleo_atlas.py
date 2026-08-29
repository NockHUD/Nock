# Tests/tools/nucleo_atlas.py
# Rasterise Nucleo "pixel" icons (~/.nucleo/skills/pixel/icons.json) into one
# WoW texture atlas (Media/PixelIcons.tga, 32-bit uncompressed) plus a Lua
# table of texcoords (UI/IconAtlas.lua), and a preview sheet on black.
#
# The pixel family is 24x24, stroke-width 2, square caps, and its paths use
# only M/L/H/V/Z (a handful of C's, ignored) -- so a line rasteriser with
# square caps reproduces it exactly at any integer scale. White on
# transparent, like the logo: SetVertexColor tints it.
#
#   python Tests/tools/nucleo_atlas.py            # atlas + lua + preview
#   python Tests/tools/nucleo_atlas.py preview    # preview only
import json, os, re, sys
from PIL import Image, ImageDraw, ImageFont

HOME = os.path.expanduser("~")
INDEX = os.path.join(HOME, ".nucleo", "skills", "pixel", "icons.json")
ADDON = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_TGA = os.path.join(ADDON, "Media", "PixelIcons.tga")
OUT_LUA = os.path.join(ADDON, "UI", "IconAtlas.lua")
OUT_PREVIEW = os.path.join(os.path.dirname(os.path.abspath(__file__)), "nucleo_preview.png")

# name we use -> Nucleo pixel label (first that exists wins)
WANT = [
    ("stage",      ["square-timeline", "equalizer"]),
    ("lesson",     ["book-open", "book", "lightbulb", "graduation-cap", "bookmark-check"]),
    ("ladder",     ["steps-indicator", "ranking", "medal"]),
    ("review",     ["chart-activity", "chart-2", "clipboard-check"]),
    ("scenarios",  ["app-stack", "grid-layout-2", "bullet-list"]),
    ("style",      ["palette", "paint-brush", "brush", "pen"]),
    ("focus",      ["arrows-expand-diagonal-3", "expand-obj", "window-expand-top-right"]),
    ("dock",       ["arrows-collapse-diagonal-3", "collapse-obj", "window-collapse"]),
    ("play",       ["media-play"]),
    ("stop",       ["media-stop"]),
    ("pause",      ["media-pause"]),
    ("prev",       ["media-previous"]),
    ("next",       ["media-next"]),
    ("skipstart",  ["media-skip-to-start"]),
    ("skipend",    ["media-skip-to-end"]),
    ("replay",     ["history", "clock-rotate-anticlockwise"]),
    ("close",      ["xmark", "cross", "circle-cross"]),
    ("gear",       ["gear"]),
    ("target",     ["target", "crosshairs-2"]),
    ("bow",        ["arrow-up-right"]),
    ("check",      ["check", "circle-check"]),
    ("warn",       ["triangle-warning", "warning"]),
    ("key",        ["key"]),
    ("clock",      ["clock", "stopwatch"]),
    ("ghost",      ["ghost", "skull"]),      # the demo's ghost hunter (Nucleo has no ghost: the skull)
    ("chevron",    ["chevron-down"]),        # the scenario picker: "this opens a list" (user, 2026-08-27)
]

CELL = 32          # atlas cell (px); the 24-grid icon sits at scale 1 centred, 4 px margin
ICON = 24
SCALE = 1          # atlas scale (1 = 24 px glyph in a 32 px cell); preview uses 4
COLS = 8

def load_index():
    d = json.load(open(INDEX, encoding="utf8"))
    return {ic["label"]: ic for ic in d["icons"]}

PATH_RE = re.compile(r'<path\b([^>]*)>', re.I)
RECT_RE = re.compile(r'<rect\b([^>]*)>', re.I)
ATTR_RE = re.compile(r'([a-zA-Z-]+)="([^"]*)"')
TOK_RE = re.compile(r'[MLHVZCmlhvzc]|-?\d*\.?\d+(?:e-?\d+)?')

def parse_paths(svg):
    out = []
    for m in PATH_RE.finditer(svg):
        attrs = dict(ATTR_RE.findall(m.group(1)))
        d = attrs.get("d", "")
        fill = attrs.get("fill", "none")
        toks = TOK_RE.findall(d)
        i, cmd, cur, start = 0, None, (0.0, 0.0), (0.0, 0.0)
        segs, poly = [], []
        def num():
            nonlocal i
            v = float(toks[i]); i += 1; return v
        while i < len(toks):
            t = toks[i]
            if t.isalpha(): cmd = t; i += 1
            if cmd in "Mm":
                x, y = num(), num()
                if cmd == "m": x, y = cur[0] + x, cur[1] + y
                cur, start = (x, y), (x, y); poly = [cur]; cmd = "L" if cmd == "M" else "l"
            elif cmd in "Ll":
                x, y = num(), num()
                if cmd == "l": x, y = cur[0] + x, cur[1] + y
                segs.append((cur, (x, y))); cur = (x, y); poly.append(cur)
            elif cmd in "Hh":
                x = num()
                if cmd == "h": x = cur[0] + x
                segs.append((cur, (x, cur[1]))); cur = (x, cur[1]); poly.append(cur)
            elif cmd in "Vv":
                y = num()
                if cmd == "v": y = cur[1] + y
                segs.append((cur, (cur[0], y))); cur = (cur[0], y); poly.append(cur)
            elif cmd in "Zz":
                segs.append((cur, start)); cur = start
            elif cmd in "Cc":
                for _ in range(6): num()      # rare; skipped
            else:
                i += 1
        out.append((segs, poly if fill not in ("none", "") else None))
    # <rect> (the family's dots and squares), with an optional affine transform
    for m in RECT_RE.finditer(svg):
        attrs = dict(ATTR_RE.findall(m.group(1)))
        x, y = float(attrs.get("x", 0)), float(attrs.get("y", 0))
        w, h = float(attrs.get("width", 0)), float(attrs.get("height", 0))
        pts = [(x, y), (x + w, y), (x + w, y + h), (x, y + h)]
        tm = re.search(r"matrix\(([^)]*)\)", attrs.get("transform", ""))
        if tm:
            a, b, c, d, e, f = [float(v) for v in re.split(r"[ ,]+", tm.group(1).strip())]
            pts = [(a * px + c * py + e, b * px + d * py + f) for px, py in pts]
        tt = re.search(r"translate\(([^)]*)\)", attrs.get("transform", ""))
        if tt:
            tx, *rest = [float(v) for v in re.split(r"[ ,]+", tt.group(1).strip())]
            ty = rest[0] if rest else 0.0
            pts = [(px + tx, py + ty) for px, py in pts]
        if attrs.get("fill", "none") != "none":
            out.append(([], pts))
    return out

def raster(svg, scale, size):
    img = Image.new("L", (size, size), 0)
    dr = ImageDraw.Draw(img)
    off = (size - ICON * scale) / 2
    w = 2 * scale
    for segs, poly in parse_paths(svg):
        if poly and len(poly) >= 3:
            dr.polygon([(off + x * scale, off + y * scale) for x, y in poly], fill=255)
        for (x0, y0), (x1, y1) in segs:
            dx, dy = x1 - x0, y1 - y0
            L = (dx * dx + dy * dy) ** 0.5
            if L < 0.05:
                cx, cy = off + x0 * scale, off + y0 * scale
                dr.rectangle([cx - w / 2, cy - w / 2, cx + w / 2 - 1, cy + w / 2 - 1], fill=255)
                continue
            ux, uy = dx / L, dy / L
            # square caps: extend both ends by half the width
            ax, ay = x0 - ux, y0 - uy
            bx, by = x1 + ux, y1 + uy
            px, py = -uy * 1.0, ux * 1.0      # half-width normal (1 unit = w/2 in grid units)
            pts = [(ax + px, ay + py), (bx + px, by + py), (bx - px, by - py), (ax - px, ay - py)]
            dr.polygon([(off + x * scale, off + y * scale) for x, y in pts], fill=255)
    rgba = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    rgba.putalpha(img)
    return rgba

# EXACT PIXELS. PIL fills a polygon's boundary pixels inclusively, so a stroke
# rectangle from x-1 to x+1 painted THREE columns: every stroke came out
# 3 px, caps a pixel long, the whole glyph a pixel wide and tall of itself
# -- the "box fitting", bolder look the user saw beside their own export
# (2026-08-26, diffed pixel for pixel). Rendering 8x over and box-filtering
# down measures true coverage; thresholding at half keeps it binary.
def raster_exact(svg, size, ss=8):
    big = raster(svg, ss * size / float(ICON), size * ss)
    small = big.resize((size, size), Image.BOX)
    a = small.split()[3].point(lambda v: 255 if v >= 128 else 0)
    out = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    out.putalpha(a)
    return out

def main():
    idx = load_index()
    picked, missing = [], []
    for name, labels in WANT:
        lab = next((l for l in labels if l in idx), None)
        if lab: picked.append((name, lab, idx[lab]["svg"]))
        else: missing.append((name, labels))
    for name, labels in missing: print("no pixel icon for", name, "tried", labels)
    # preview at 4x on black, labelled
    S = 4
    cw, ch = ICON * S + 40, ICON * S + 34
    cols = 6
    rows = (len(picked) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * cw, rows * ch), (0, 0, 0))
    font = ImageFont.load_default()
    for k, (name, lab, svg) in enumerate(picked):
        im = raster_exact(svg, ICON).resize((ICON * S, ICON * S), Image.NEAREST)
        x, y = (k % cols) * cw + 20, (k // cols) * ch + 6
        sheet.paste(im, (x, y), im)
        ImageDraw.Draw(sheet).text((x, y + ICON * S + 4), f"{name}  ({lab})", fill=(170, 170, 165), font=font)
    sheet.save(OUT_PREVIEW)
    print("preview", OUT_PREVIEW, len(picked), "icons")
    if len(sys.argv) > 1 and sys.argv[1] == "preview": return
    # the atlas: 32 px cells, glyph at 1x (24 px) centred, power-of-two sheet
    n = len(picked)
    rows = (n + COLS - 1) // COLS
    W = COLS * CELL
    H = 32
    while H < rows * CELL: H *= 2
    atlas = Image.new("RGBA", (W, H), (255, 255, 255, 0))
    lua = ["-- UI/IconAtlas.lua", "-- GENERATED by Tests/tools/nucleo_atlas.py from the Nucleo pixel family.",
           "-- name -> { left, right, top, bottom } texcoords into Media/PixelIcons.tga;",
           "-- white on transparent, tint with SetVertexColor. Nucleo icons: nucleoapp.com, licensed.",
           "local Nock = rawget(_G, \"Nock\")", "Nock.IconAtlas = {", f"  texture = \"Interface\\\\AddOns\\\\Nock\\\\Media\\\\PixelIcons\",",
           f"  size = {{ {W}, {H} }}, cell = {CELL},", "  coords = {"]
    for k, (name, lab, svg) in enumerate(picked):
        im = raster_exact(svg, ICON)
        cx, cy = (k % COLS) * CELL + (CELL - ICON) // 2, (k // COLS) * CELL + (CELL - ICON) // 2
        atlas.paste(im, (cx, cy), im)
        cx, cy = (k % COLS) * CELL, (k // COLS) * CELL
        lua.append(f"    {name:10s} = {{ {cx / W:.6f}, {(cx + CELL) / W:.6f}, {cy / H:.6f}, {(cy + CELL) / H:.6f} }},  -- {lab}")
    lua += ["  },"]
    atlas.save(OUT_TGA, compression=None)
    # ...and every icon as its OWN 24x24 TGA (Media/Icons/<name>.tga), the
    # glyph filling the file, NO padding. Why this and only this is crisp
    # in-game (2026-08-26, the user's own 24x24 file proved it): the client
    # builds a mip chain for power-of-two textures and samples with a bias
    # that blends the half-size mip in even at 1:1 -- the 256 px sheet and a
    # 32x32 file both came out soft and a shade large -- while a 24x24
    # (non-power-of-two) texture gets no mips and is drawn as it is.
    icon_dir = os.path.join(ADDON, "Media", "Icons")
    os.makedirs(icon_dir, exist_ok=True)
    lua += [f"  fileCell = {ICON},   -- the per-icon files are the bare {ICON}-grid, no padding", "  files = {"]
    for k, (name, lab, svg) in enumerate(picked):
        raster_exact(svg, ICON).save(os.path.join(icon_dir, name + ".tga"), compression=None)
        bs = chr(92) * 2   # a Lua-escaped backslash
        lua.append(f"    {name:10s} = \"Interface{bs}AddOns{bs}Nock{bs}Media{bs}Icons{bs}{name}\",")
    lua += ["  },", "}"]
    lua.append("")
    open(OUT_LUA, "w", encoding="utf8", newline="\n").write("\n".join(lua))
    print("atlas", OUT_TGA, W, "x", H, "->", OUT_LUA)

if __name__ == "__main__":
    main()
