"""The style themes' art (StyleThemes.lua), all drawn from scratch here, none of
it the game's. Usage, from the repo root: python Media/make_theme_art.py

For each theme:
Textures/Bars/<Bar>.tga: a bar fill, 256x32, white shaded in grey (the game
tints it the bar's color), opaque, as Media/make_bar_textures.py's.
Textures/Themes/<Name>Corner.tga: a panel's top left corner ornament, 64x64,
pale on clear (tinted the theme's ornament color; the other three corners are
this one flipped).
Textures/Themes/<Name>Grain.tga: a panel's surface, 128x128, grey, opaque, and
tiling (tinted the panel's color).
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SS = 8           # (corners are drawn this many times too big, then shrunk: clean edges)
C = 64           # a corner's size
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
THEMES = os.path.join(ROOT, "Textures", "Themes")
BARS = os.path.join(ROOT, "Textures", "Bars")
rng = np.random.default_rng(7)


def save(im, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    im.save(path, compression=None)


# Bars. level(u, v) over 0..1 gives the grey at each point.
def bar(level):
    w, h = 256, 32
    u = (np.arange(w) + 0.5)[None, :] / w
    v = (np.arange(h) + 0.5)[:, None] / h
    grey = np.clip(level(u + 0 * v, v + 0 * u), 0, 1)
    out = np.dstack([grey * 255] * 3 + [np.full(grey.shape, 255.0)])
    return Image.fromarray(out.astype(np.uint8), "RGBA")


def smooth(t):
    t = np.clip(t, 0, 1)
    return t * t * (3 - 2 * t)


def noise1(n, scale):
    """Tiling smooth noise along a line, -1 to 1."""
    k = rng.normal(size=n)
    f = np.fft.rfft(k)
    f[int(n / scale) + 1:] = 0
    out = np.fft.irfft(f, n)
    return out / np.abs(out).max()


def gilt(u, v):
    # (Beaten gold: a bright rim above, a dark rim below, a soft band of light.)
    body = 0.70 + 0.22 * np.exp(-((v - 0.32) / 0.2) ** 2)
    body = body + 0.035 * noise1(256, 18)[None, :]
    rim = np.where(v < 0.07, 1.0, np.where(v > 0.92, 0.42, body))
    return rim


def forged(u, v):
    # (Hammered iron: dents along the bar over a heavy bevel.)
    dents = (noise1(256, 26)[None, :] * noise1(32, 6)[:, None]) * 0.08
    body = 0.84 - 0.34 * smooth((v - 0.2) / 0.8) + dents
    return np.where(v < 0.06, 1.0, np.where(v > 0.9, 0.3, body))


def lunar(u, v):
    # (Moonlight: lit softly from the middle, fading to the edges.)
    return 0.62 + 0.38 * np.exp(-((v - 0.44) / 0.3) ** 2)


def rime(u, v):
    # (Ice: a hard bright facet over the top third, a thin line of light low down.)
    top = np.where(v < 0.36, 0.98 - 0.16 * v / 0.36, 0.62 + 0.14 * smooth((v - 0.36) / 0.64))
    glint = 0.2 * np.exp(-((v - 0.86) / 0.04) ** 2)
    return top + glint


def reel(u, v):
    # (A strip of film: flat, a hairline at each edge.)
    return np.where((v < 0.05) | (v > 0.95), 0.55, 0.9 - 0.08 * v)


# Grains: tiling noise, shaped.
def field(n, low, high):
    """Tiling noise with detail between the two wave counts, 0 to 1."""
    f = np.fft.fft2(rng.normal(size=(n, n)))
    fy = np.abs(np.fft.fftfreq(n))[:, None] * n
    fx = np.abs(np.fft.fftfreq(n))[None, :] * n
    r = np.sqrt(fx ** 2 + fy ** 2)
    f = f * ((r >= low) & (r <= high))
    out = np.real(np.fft.ifft2(f))
    return (out - out.min()) / (out.max() - out.min())


def streaks(n, along, across):
    f = np.fft.fft2(rng.normal(size=(n, n)))
    fy = np.abs(np.fft.fftfreq(n))[:, None] * n
    fx = np.abs(np.fft.fftfreq(n))[None, :] * n
    f = f * ((fx <= along) & (fy <= across))
    out = np.real(np.fft.ifft2(f))
    return (out - out.min()) / (out.max() - out.min())


def grain(values):
    grey = np.clip(values, 0, 1) * 255
    return Image.fromarray(np.dstack([grey] * 3 + [np.full(grey.shape, 255.0)]).astype(np.uint8), "RGBA")


def grains():
    n = 128
    return {
        # (Vellum: long fibres over slow blotches.)
        "Codex": 0.80 + 0.13 * (streaks(n, 5, 44) - 0.5) + 0.26 * (field(n, 1, 5) - 0.5),
        # (Brushed iron with pits.)
        "Forge": 0.80 + 0.26 * (streaks(n, 60, 3) - 0.5) + 0.14 * (field(n, 18, 50) - 0.5),
        # (Night mist.)
        "Glade": 0.82 + 0.36 * (field(n, 1, 4) - 0.5) + 0.05 * (field(n, 20, 50) - 0.5),
        # (Frost: fine crackle, thin bright threads.)
        "Rime": 0.80 + 0.30 * np.abs(field(n, 5, 16) - 0.5) ** 0.6 - 0.1,
        # (Film grain.)
        "Reel": 0.84 + 0.16 * (rng.random((n, n)) - 0.5),
    }


# Corners: drawn big on clear, in pale greys.
def canvas():
    im = Image.new("RGBA", (C * SS, C * SS), (0, 0, 0, 0))
    return im, ImageDraw.Draw(im)


def S(*values):
    return [x * SS for x in values]


def finish(im, shadow=True):
    """Shrunk to size, with a dark halo so it reads on any panel."""
    if shadow:
        alpha = im.getchannel("A").filter(ImageFilter.GaussianBlur(SS * 0.9))
        halo = Image.new("RGBA", im.size, (0, 0, 0, 0))
        halo.putalpha(alpha.point(lambda a: int(a * 0.55)))
        im = Image.alpha_composite(halo, im)
    return im.resize((C, C), Image.LANCZOS)


def stroke(d, points, width, fill):
    """A line of changing width: points as (x, y, w)."""
    for (x1, y1, w1), (x2, y2, w2) in zip(points, points[1:]):
        steps = max(2, int(math.hypot(x2 - x1, y2 - y1) * SS / 2))
        for i in range(steps + 1):
            t = i / steps
            x, y, w = x1 + (x2 - x1) * t, y1 + (y2 - y1) * t, (w1 + (w2 - w1) * t) * width
            r = max(w * SS / 2, 0.5)
            d.ellipse((x * SS - r, y * SS - r, x * SS + r, y * SS + r), fill=fill)


def spiral(cx, cy, r0, turns, start, sense=1, w0=1.0, w1=0.3):
    pts = []
    n = int(40 * turns) + 2
    for i in range(n):
        t = i / (n - 1)
        a = start + sense * t * turns * 2 * math.pi
        r = r0 * (1 - 0.86 * t)
        pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r, w0 + (w1 - w0) * t))
    return pts


def codex():
    # (Filigree: a long tapering rule down each edge, each curling into a
    # scroll, a lozenge on the corner between them.)
    im, d = canvas()
    gold, soft = (255, 246, 214, 255), (225, 205, 160, 255)
    for flip in (False, True):
        def P(pts):
            return [(y, x, w) if flip else (x, y, w) for x, y, w in pts]
        stroke(d, P([(9, 5.5, 1.5), (34, 5.5, 1.1), (58, 5.5, 0.15)]), 1.3, gold)
        stroke(d, P([(14, 9.5, 0.7), (30, 9.5, 0.5), (42, 9.5, 0.1)]), 1.0, soft)
        stroke(d, P(spiral(27, 15.5, 6.2, 1.35, -math.pi / 2, 1, 1.25, 0.35)), 1.2, gold)
        stroke(d, P(spiral(41, 13.2, 3.4, 1.15, -math.pi / 2, 1, 0.8, 0.25)), 1.1, soft)
        # (a leaf off the rule)
        leaf = [(47, 5.5), (51, 8.8), (56, 9.6), (52, 6.4)]
        d.polygon([tuple(S(*(p[::-1] if flip else p))) for p in leaf], fill=soft)
    d.polygon([tuple(S(*p)) for p in ((8, 1.5), (14.5, 8), (8, 14.5), (1.5, 8))], fill=gold)
    d.polygon([tuple(S(*p)) for p in ((8, 5), (11, 8), (8, 11), (5, 8))], fill=(120, 92, 42, 255))
    d.ellipse(S(16.2, 16.2, 20.8, 20.8), fill=gold)
    return finish(im)


def forge():
    # (A bracket of riveted plate, chamfered, lit along its top left.)
    im, d = canvas()
    plate = [(0, 0), (46, 0), (46, 5), (38, 13), (13, 13), (13, 38), (5, 46), (0, 46)]
    d.polygon([tuple(S(*p)) for p in plate], fill=(168, 164, 158, 255))
    inner = [(1.6, 1.6), (44, 1.6), (44, 4), (37, 11), (11, 11), (11, 37), (4, 44), (1.6, 44)]
    d.polygon([tuple(S(*p)) for p in inner], fill=(122, 118, 113, 255))
    d.line([tuple(S(*p)) for p in ((1.6, 44), (1.6, 1.6), (44, 1.6))], fill=(236, 232, 224, 255), width=int(1.1 * SS))
    for x, y in ((6.5, 6.5), (30, 6.5), (6.5, 30)):
        d.ellipse(S(x - 3.2, y - 3.2, x + 3.2, y + 3.2), fill=(60, 57, 54, 255))
        d.ellipse(S(x - 2.4, y - 2.6, x + 2.2, y + 2), fill=(214, 208, 198, 255))
        d.ellipse(S(x - 1.6, y - 1.9, x + 0.2, y - 0.2), fill=(255, 252, 244, 255))
    return finish(im)


def glade():
    # (A crescent moon in the corner, a vine leaving it each way, leaf by leaf.)
    im, d = canvas()
    pale, soft = (244, 250, 246, 255), (200, 224, 214, 255)
    moon = Image.new("L", im.size, 0)
    m = ImageDraw.Draw(moon)
    m.ellipse(S(2, 2, 20, 20), fill=255)
    m.ellipse(S(7.5, 0, 24, 16.5), fill=0)
    im.paste(Image.new("RGBA", im.size, pale), (0, 0), moon)
    d = ImageDraw.Draw(im)

    def leaf(x, y, angle, size, fill):
        pts = []
        for i in range(21):
            t = i / 20
            half = math.sin(t * math.pi) ** 0.8 * size * 0.3
            pts.append((t * size, half))
        pts += [(p[0], -p[1]) for p in reversed(pts)]
        ca, sa = math.cos(angle), math.sin(angle)
        d.polygon([tuple(S(x + p[0] * ca - p[1] * sa, y + p[0] * sa + p[1] * ca)) for p in pts], fill=fill)

    for flip in (False, True):
        vine = []
        for i in range(41):
            t = i / 40
            x = 17 + t * 42
            y = 5.5 + 2.3 * math.sin(t * 9.5)
            vine.append((x, y, 1.0 - 0.8 * t))
        stroke(d, [(y, x, w) if flip else (x, y, w) for x, y, w in vine], 1.1, soft)
        for i, t in enumerate((0.12, 0.3, 0.48, 0.66, 0.84)):
            x, y = 17 + t * 42, 5.5 + 2.3 * math.sin(t * 9.5)
            side = 1 if i % 2 == 0 else -1
            size = 8.5 * (1 - 0.62 * t)
            a = 0.55 * side
            if flip:
                x, y, a = y, x, math.pi / 2 - a
            leaf(x, y, a, size, pale if i % 2 == 0 else soft)
    d.ellipse(S(21.5, 21.5, 24, 24), fill=pale)
    d.ellipse(S(27, 19, 28.6, 20.6), fill=soft)
    d.ellipse(S(19, 27, 20.6, 28.6), fill=soft)
    return finish(im)


def rime_corner():
    # (Ice crystals growing out of the corner, each cut in two facets.)
    im, d = canvas()

    def shard(angle, length, width):
        ca, sa = math.cos(angle), math.sin(angle)
        px, py = -sa, ca
        base = (2.5, 2.5)
        tip = (base[0] + ca * length, base[1] + sa * length)
        mid = (base[0] + ca * length * 0.32, base[1] + sa * length * 0.32)
        a = (mid[0] + px * width, mid[1] + py * width)
        b = (mid[0] - px * width, mid[1] - py * width)
        d.polygon([tuple(S(*p)) for p in (base, a, tip)], fill=(255, 255, 255, 255))
        d.polygon([tuple(S(*p)) for p in (base, b, tip)], fill=(176, 196, 214, 255))

    for angle, length, width in ((0.04, 56, 3.2), (1.53, 56, 3.2), (0.27, 34, 2.8), (1.3, 34, 2.8), (0.52, 22, 2.8),
                                 (1.05, 22, 2.8), (0.785, 30, 4)):
        shard(angle, length, width)
    for x, y, s in ((41, 13, 1.6), (13, 41, 1.6), (29, 22, 1.2), (22, 29, 1.2)):
        d.polygon([tuple(S(*p)) for p in ((x, y - s * 2), (x + s, y), (x, y + s * 2), (x - s, y))], fill=(255, 255, 255, 255))
    return finish(im)


def reel_corner():
    # (A cinema's crop mark: a hairline L and a row of film sprockets.)
    im, d = canvas()
    white = (255, 255, 255, 255)
    d.rectangle(S(2, 2, 40, 3.2), fill=white)
    d.rectangle(S(2, 2, 3.2, 40), fill=white)
    for i in range(4):
        x = 9 + i * 7
        d.rounded_rectangle(S(x, 6, x + 3.8, 9.4), radius=SS * 0.6, fill=(222, 222, 222, 255))
        d.rounded_rectangle(S(6, x, 9.4, x + 3.8), radius=SS * 0.6, fill=(222, 222, 222, 255))
    return finish(im, shadow=False)


def main():
    for name, level in (("Gilt", gilt), ("Forged", forged), ("Lunar", lunar), ("Rime", rime), ("Reel", reel)):
        save(bar(level), os.path.join(BARS, name + ".tga"))
    for name, values in grains().items():
        save(grain(values), os.path.join(THEMES, name + "Grain.tga"))
    for name, draw in (("Codex", codex), ("Forge", forge), ("Glade", glade), ("Rime", rime_corner), ("Reel", reel_corner)):
        save(draw(), os.path.join(THEMES, name + "Corner.tga"))


if __name__ == "__main__":
    main()
