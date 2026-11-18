"""Sunset bar fills for the sunset style theme: full color (not grey to tint), so the
bar keeps its own gradient; the theme draws it with a white vertex color. Our own,
drawn from scratch here: a dusk sky with palm silhouettes a shade darker, faint.

Sunset (256x32): the sky runs along the bar, blue at the empty end to gold at the
full end, light at the top and shaded at the bottom: for thin bars (nameplates,
cast bars), where a top-to-bottom sky would only be stripes.
SunsetTall (256x64): the sky top to bottom, blue over magenta over orange, with
bigger palms: for tall bars (unit frames, slabs).
SunsetGrey, SunsetTallGrey: their twins in grey, the same palms, for bars the
game or a page tints (mana, casts, timers): the full-color ones under a color
go muddy (StylePages.lua, ns.StyleTextureFull).

Usage: python Media/make_sunset_art.py [preview.png]  (writes Textures/Bars;
with a path, also a picture of both at the sizes they show in game.)"""
import math
import os
import random
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BARS = os.path.join(ROOT, "Textures", "Bars")
SS = 4  # (drawn this many times bigger, then shrunk: smooth edges)

# The sky, as stops from 0 (top / empty end) to 1 (bottom / full end).
SKY = [
    (0.00, (58, 91, 208)),    # blue
    (0.28, (142, 68, 200)),   # purple
    (0.52, (232, 52, 168)),   # magenta
    (0.70, (255, 92, 132)),   # pink
    (0.86, (255, 138, 61)),   # orange
    (1.00, (255, 193, 74)),   # gold
]


def sky(t):
    t = min(max(t, 0.0), 1.0)
    for (a, ca), (b, cb) in zip(SKY, SKY[1:]):
        if t <= b:
            k = (t - a) / (b - a)
            k = k * k * (3 - 2 * k)
            return tuple(ca[i] + (cb[i] - ca[i]) * k for i in range(3))
    return SKY[-1][1]


def palm(d, x, base, height, lean, seed, frond=1.0):
    """One palm on a supersampled L image: a curved trunk thinning upward and a
    crown of drooping fronds, each a spine with leaflets along it."""
    rng = random.Random(seed)
    top = (x + lean * height, base - height)
    # (Trunk: a gentle bow, thick at the foot.)
    steps = 40
    pts = []
    for i in range(steps + 1):
        t = i / steps
        bow = math.sin(t * math.pi) * lean * height * 0.25
        pts.append((x + (top[0] - x) * t ** 1.3 + bow, base - height * t))
    for i in range(steps):
        w = height * (0.06 - 0.035 * i / steps)
        d.line([pts[i], pts[i + 1]], fill=255, width=max(1, int(w)))
    cx, cy = pts[-1]
    # (Fronds: spread round the crown, the side ones drooping most.)
    # (From a little below level on one side, over the top, to the other side.)
    count = rng.randint(8, 10)
    for k in range(count):
        ang = -math.pi * (-0.12 + 1.24 * k / (count - 1)) + rng.uniform(-0.1, 0.1)
        length = height * frond * rng.uniform(0.5, 0.68)
        droop = 0.55 * abs(math.cos(ang)) ** 0.8 + 0.12
        spine = []
        for i in range(24):
            t = i / 23
            px = cx + math.cos(ang) * length * t
            py = cy + math.sin(ang) * length * t + droop * length * t * t
            spine.append((px, py))
        d.line(spine, fill=255, width=max(1, int(height * 0.022)))
        # (Leaflets both sides, longest in the middle of the frond, angled outward.)
        for i in range(2, 23):
            t = i / 23
            (ax, ay), (bx, by) = spine[i - 1], spine[i]
            dx, dy = bx - ax, by - ay
            n = math.hypot(dx, dy) or 1
            dx, dy = dx / n, dy / n
            leaf = height * 0.16 * math.sin(t * math.pi) ** 0.7 * frond
            for side in (-1, 1):
                nx, ny = -dy * side, dx * side
                ex = bx + (nx * 0.8 + dx * 0.6) * leaf
                ey = by + (ny * 0.8 + dy * 0.6) * leaf + leaf * 0.35
                d.polygon([(bx, by), (ex, ey), (bx + dx * leaf * 0.25, by + dy * leaf * 0.25)], fill=255)


def silhouettes(w, h, palms):
    big = Image.new("L", (w * SS, h * SS), 0)
    d = ImageDraw.Draw(big)
    for p in palms:
        x, base, height, lean, seed = p[:5]
        palm(d, x * SS, base * SS, height * SS, lean, seed, *p[5:])
    return big.resize((w, h), Image.LANCZOS)


def build(w, h, along, palms, palm_alpha, light, shade, grey=False):
    """along: the sky runs along the bar (True) or top to bottom (False).
    grey: white shaded in grey instead of the sky, for tinting."""
    trees = silhouettes(w, h, palms)
    out = Image.new("RGB", (w, h))
    px = out.load()
    tp = trees.load()
    for y in range(h):
        v = y / (h - 1)
        # (Light along the top, shade along the bottom: depth, never one flat color.)
        lift = light * max(0.0, 1 - v / 0.35) ** 2
        dark = shade * max(0.0, (v - 0.6) / 0.4) ** 1.5
        for x in range(w):
            c = (238, 238, 238) if grey else sky(x / (w - 1) if along else v)
            # (Palms: the same sky, darker and a touch more purple, faint.)
            a = tp[x, y] / 255 * palm_alpha
            if grey:
                c = tuple(ch * (1 - a * 0.5) for ch in c)
            else:
                c = (c[0] * (1 - a * 0.55), c[1] * (1 - a * 0.6), c[2] * (1 - a * 0.3))
            c = tuple(ch + (255 - ch) * lift for ch in c)
            c = tuple(ch * (1 - dark) for ch in c)
            px[x, y] = tuple(max(0, min(255, int(ch + 0.5))) for ch in c)
    return out


def save(img, name):
    rgba = img.convert("RGBA")
    rgba.save(os.path.join(BARS, name + ".tga"), compression=None)
    return rgba


# (Thin bar: crowns along it, trunks cut off below; big enough to read at 10 px.)
THIN = [(14, 60, 50, 0.10, 1, 0.75), (74, 58, 46, -0.14, 2, 0.75), (136, 62, 52, 0.08, 3, 0.75),
        (196, 58, 47, -0.06, 4, 0.75), (250, 62, 51, 0.16, 5, 0.75)]
TALL = [(30, 92, 76, 0.12, 11, 0.8), (104, 90, 66, -0.10, 12, 0.8), (178, 96, 80, 0.06, 13, 0.8),
        (240, 90, 70, -0.15, 14, 0.8)]


def main():
    thin = save(build(256, 32, True, THIN, 0.6, 0.28, 0.3), "Sunset")
    tall = save(build(256, 64, False, TALL, 0.45, 0.22, 0.14), "SunsetTall")
    save(build(256, 32, True, THIN, 0.6, 0.2, 0.22, grey=True), "SunsetGrey")
    save(build(256, 64, False, TALL, 0.45, 0.16, 0.14, grey=True), "SunsetTallGrey")
    if len(sys.argv) > 1:
        preview(thin, tall, sys.argv[1])


def preview(thin, tall, path):
    """Both at their game sizes on a dark ground, plus a 4x look, with the theme's
    double line (plum outside, gold inside) round the in-game sizes."""
    W = 900
    sheet = Image.new("RGB", (W, 520), (18, 14, 26))
    d = ImageDraw.Draw(sheet)
    y = 16

    def framed(img, w, h, fill=1.0):
        nonlocal y
        bar = Image.new("RGB", (w, h), (40, 20, 50))
        fw = max(1, int(w * fill))
        # (A status bar crops its texture to the fill, it doesn't squash it.)
        crop = img.crop((0, 0, max(1, int(img.width * fill)), img.height)).resize((fw, h), Image.LANCZOS)
        bar.paste(crop.convert("RGB"), (0, 0))
        d.rectangle((14, y - 2, 16 + w + 1, y + h + 1), outline=(58, 10, 74), width=2)
        d.rectangle((16, y, 16 + w - 1, y + h - 1), outline=(255, 176, 0), width=1)
        sheet.paste(bar.crop((1, 1, w - 1, h - 1)), (17, y + 1))
        y += h + 14

    for fill in (1.0, 0.62, 0.3):
        framed(thin, 140, 12, fill)
    framed(thin, 220, 18)
    framed(tall, 180, 44)
    framed(tall, 180, 44, 0.55)
    sheet.paste(thin.convert("RGB").resize((1024 * W // 1100, 128 * W // 1100), Image.NEAREST), (300, 16))
    sheet.paste(tall.convert("RGB").resize((512, 128)), (300, 150))
    sheet.save(path)


if __name__ == "__main__":
    main()
