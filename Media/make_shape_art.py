"""The shapes the style themes can give panels, bars and portraits (StyleThemes.lua),
drawn from scratch here. Usage, from the repo root: python Media/make_shape_art.py

Textures/Themes/Shapes/:
Panel<Name>.tga and Panel<Name>Edge.tga: a panel's fill and its line, 128x128, white
on clear, drawn as nine pieces whose corners are a quarter each (ns.DressThemeSlice);
twice the size they're drawn at, so a corner stays smooth at any UI scale.
Tail.tga and TailEdge.tga: a chat bubble's tail and the line down its sides, 128x128.
Bar<Name>.tga: a mask for a bar, 256x32, white on clear: what's clear is cut away.
Portrait<Name>.tga and Portrait<Name>Ring.tga: a portrait's mask and the line
round it, 128x128, white on clear. Portrait<Name>Ring2 to 4.tga: the same line worn
another way (its cracks, nicks and mottling elsewhere), so frames side by side don't
match. Portrait<Name>Cut.tga: what cuts the real one.
MinimapRimShade.tga: dark just inside the minimap's ring (the game's own, tinted),
256x256, its circle at MINIMAP_INNER of the way out. SquareFrameMask.tga: a square
button's frame alone, for tinting just that.
PortraitBackEye.tga: an eye behind a circle portrait (Void Whisper), 256x256.
"""
import math
import os
import random

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Textures", "Themes", "Shapes")
SS = 8


def stamp(size, draw):
    """A white shape on clear, from draw(d, scale) on a big canvas."""
    w, h = size
    mask = Image.new("L", (w * SS, h * SS), 0)
    draw(ImageDraw.Draw(mask), SS)
    return mask.resize(size, Image.LANCZOS)


def white(alpha):
    out = Image.new("RGBA", alpha.size, (255, 255, 255, 0))
    out.putalpha(alpha)
    return out


def save(alpha, name):
    os.makedirs(OUT, exist_ok=True)
    white(alpha).save(os.path.join(OUT, name + ".tga"), compression=None)


def outline(big, width):
    """The band just inside a big (SS times) shape."""
    inner = big.filter(ImageFilter.MinFilter(2 * width * SS // 2 * 2 + 1))
    return ImageChops.subtract(big, inner)


def even_outline(big, width):
    """The band just inside a big shape, the same width all round. outline()'s square
    filter cuts 1.4 times deeper on the diagonals, which shows on a curved ring."""
    half = big.resize((big.width // 2, big.height // 2), Image.LANCZOS)
    r = width * SS // 2
    inner = half
    for i in range(64):
        a = i * 2 * math.pi / 64
        inner = ImageChops.darker(inner, ImageChops.offset(half, round(r * math.cos(a)), round(r * math.sin(a))))
    return ImageChops.subtract(half, inner)


def poly(points):
    def draw(d, s):
        d.polygon([(x * s, y * s) for x, y in points], fill=255)
    return draw


# Panels: 64x64, the shape's corners inside the 16 pixel corner pieces.
def panel_round(d, s):
    d.rounded_rectangle((1 * s, 1 * s, 63 * s, 63 * s), radius=13 * s, fill=255)


def panel_chamfer(d, s):
    c = 7
    poly([(1 + c, 1), (63 - c, 1), (63, 1 + c), (63, 63 - c), (63 - c, 63), (1 + c, 63), (1, 63 - c), (1, 1 + c)])(d, s)


def panel_blade(d, s):
    c = 9
    poly([(1 + c, 1), (63, 1), (63, 63 - c), (63 - c, 63), (1, 63), (1, 1 + c)])(d, s)


def panel_notch(d, s):
    d.rectangle((1 * s, 1 * s, 63 * s, 63 * s), fill=255)
    r = 7
    for cx, cy in ((1, 1), (63, 1), (1, 63), (63, 63)):
        d.ellipse(((cx - r) * s, (cy - r) * s, (cx + r) * s, (cy + r) * s), fill=0)


def panel_sigil(d, s):
    # (Each corner pulled in to a point.)
    a, b = 9, 5
    poly([(1 + a, 1), (63 - a, 1), (63 - b, 1 + b), (63, 1 + a), (63, 63 - a), (63 - b, 63 - b), (63 - a, 63),
          (1 + a, 63), (1 + b, 63 - b), (1, 63 - a), (1, 1 + a), (1 + b, 1 + b)])(d, s)


def panel_veil(d, s):
    # (Soft above, sharp below.)
    d.rounded_rectangle((1 * s, 1 * s, 63 * s, 63 * s), radius=15 * s, fill=255, corners=(True, True, False, False))


def mirrored(corner):
    """A rectangle with its corner cut the same at all four: corner's points run from the
    top edge to the left edge, and go round clockwise from the left edge."""
    top_left = list(corner)
    top_right = [(64 - x, y) for x, y in top_left]
    bottom_right = [(64 - x, 64 - y) for x, y in reversed(top_left)]
    bottom_left = [(x, 64 - y) for x, y in top_left]
    return poly(list(reversed(top_left)) + top_right + bottom_right + bottom_left)


def panel_soft(d, s):
    d.rounded_rectangle((1 * s, 1 * s, 63 * s, 63 * s), radius=6 * s, fill=255)


def panel_leaf(d, s):
    # (Two corners swept round, two left sharp: a leaf's outline.)
    d.rounded_rectangle((1 * s, 1 * s, 63 * s, 63 * s), radius=15 * s, fill=255, corners=(False, True, False, True))


PANELS = {"Round": panel_round, "Chamfer": panel_chamfer, "Blade": panel_blade, "Notch": panel_notch,
          "Sigil": panel_sigil, "Veil": panel_veil, "Leaf": panel_leaf, "Soft": panel_soft,
          # (Art deco steps, a plate's square-cut corners, a gem's two facets.)
          "Deco": lambda d, s: mirrored([(9, 1), (9, 5), (5, 5), (5, 9), (1, 9)])(d, s),
          "Plate": lambda d, s: mirrored([(7, 1), (7, 7), (1, 7)])(d, s),
          "Facet": lambda d, s: mirrored([(8, 1), (3, 3), (1, 8)])(d, s)}


def panels():
    for name, draw in PANELS.items():
        big = Image.new("L", (128 * SS, 128 * SS), 0)
        draw(ImageDraw.Draw(big), SS * 2)
        save(big.resize((128, 128), Image.LANCZOS), "Panel" + name)
        save(outline(big, 4).resize((128, 128), Image.LANCZOS), "Panel" + name + "Edge")


def tail():
    # (Its fill breaks the panel's bottom line and its side lines carry on from there.)
    # (Drawn at 4 times its 24x18 size in the game, then squared up for the file.)
    w, h = 96, 72
    big = Image.new("L", (w * SS, h * SS), 0)
    poly([(2, 0), (94, 0), (48, 70)])(ImageDraw.Draw(big), SS)
    save(big.resize((128, 128), Image.LANCZOS), "Tail")
    # (From its very top: that sits level with the top of the panel's line.)
    for name, width in (("TailEdge", 16), ("TailEdgeThin", 8)):
        side = Image.new("L", (w * SS, h * SS), 0)
        d = ImageDraw.Draw(side)
        for a, b in (((2, 0), (48, 70)), ((94, 0), (48, 70))):
            d.line([(a[0] * SS, a[1] * SS), (b[0] * SS, b[1] * SS)], fill=255, width=width * SS)
        side = ImageChops.multiply(side, big)
        save(side.resize((128, 128), Image.LANCZOS), name)


# Bars: 256x32. A mask stretches with its bar, so the ends are drawn long.
def bar_capsule(d, s):
    d.rounded_rectangle((0, 1 * s, 256 * s, 31 * s), radius=15 * s, fill=255)


def bar_chisel(d, s):
    poly([(0, 1), (256, 1), (256, 17), (240, 31), (0, 31)])(d, s)


def bar_bevel(d, s):
    poly([(0, 9), (8, 1), (248, 1), (256, 9), (256, 23), (248, 31), (8, 31), (0, 23)])(d, s)


def bar_soft(d, s):
    d.rounded_rectangle((0, 1 * s, 256 * s, 31 * s), radius=7 * s, fill=255)


# Portraits: 128x128.
def regular(sides, start):
    return [(64 + 62 * math.cos(start + i * 2 * math.pi / sides), 64 + 62 * math.sin(start + i * 2 * math.pi / sides))
            for i in range(sides)]


def portrait_arch(d, s):
    # (A gothic lancet: two arcs meeting at a point, straight sides below.)
    r, spring = 88, 86
    left = []
    for i in range(33):
        # (arc centered on the right of the opening, from the spring line up to the tip)
        ang = math.pi + (i / 32) * math.acos((r - 124 / 2) / r)
        left.append((2 + r + r * math.cos(ang), spring + r * math.sin(ang)))
    right = [(128 - x, y) for x, y in reversed(left)]
    pts = left + right + [(126, 126), (2, 126)]
    d.polygon([(x * s, y * s) for x, y in pts], fill=255)


def portrait_eye(d, s):
    # (Two arcs meeting in a point at top and bottom.)
    half_h, half_w = 62, 54
    r = (half_h ** 2 + half_w ** 2) / (2 * half_w)
    reach = math.asin(half_h / r)
    right = [(64 + half_w - r + r * math.cos(a), 64 + r * math.sin(a))
             for a in (-reach + i * 2 * reach / 48 for i in range(49))]
    left = [(128 - x, y) for x, y in reversed(right)]
    d.polygon([(x * s, y * s) for x, y in right + left], fill=255)


def portrait_shield(d, s):
    # (Flat across the top, straight sides, a full round bottom.)
    side = []
    for i in range(49):
        t = i / 48
        side.append((64 + 56 * max(0, 1 - t ** 3) ** 0.5, 8 + 116 * t))
    d.polygon([(x * s, y * s) for x, y in [(8, 8)] + side + [(128 - x, y) for x, y in reversed(side)]], fill=255)


def portrait_petal(d, s):
    # (Rounded, with two corners left sharp: the Leaf panel's outline.)
    d.rounded_rectangle((4 * s, 4 * s, 124 * s, 124 * s), radius=50 * s, fill=255, corners=(False, True, False, True))


PORTRAITS = {"Hex": poly(regular(6, math.pi / 6)), "Diamond": poly([(64, 2), (126, 64), (64, 126), (2, 64)]),
             "Arch": portrait_arch, "Eye": portrait_eye, "Shield": portrait_shield, "Petal": portrait_petal,
             "Octagon": poly(regular(8, math.pi / 8)),
             "Crystal": poly(regular(6, 0)),
             "Cut": poly([(22, 2), (106, 2), (126, 22), (126, 106), (106, 126), (22, 126), (2, 106), (2, 22)])}


def noise(size, seed, blur):
    """Grey noise, the same each time the art's drawn, spread back out to full range."""
    rng = random.Random(seed)
    im = Image.new("L", size)
    im.putdata([rng.randrange(256) for _ in range(size[0] * size[1])])
    im = im.filter(ImageFilter.GaussianBlur(blur))
    low, high = im.getextrema()
    return im.point(lambda v: (v - low) * 255 // max(1, high - low))


def eye_iris(n, c, d, a, shape):
    """What's in Void Whisper's eye, round the circle (radius d/2): fine fibers
    reaching out from it, faintly wavy, and a few vessels winding in from the edge,
    branching and thinning to a hair, each with a lighter core. Kept inside the worn
    edge. Gives (fibers, vessels, cores, halo, room) as numpy arrays: fibers about -3
    to 3 (dark below 0, light above), the rest 0 to 1."""
    import numpy as np
    rc = d / 2
    f = rc / 164  # (the mockup's scale: its numbers below)
    # (Room: inside the eye's worn edge, out of the circle.)
    small = shape.resize((n // 4, n // 4), Image.BILINEAR).point(lambda v: 255 if v > 128 else 0)
    inner = small.filter(ImageFilter.MinFilter(2 * round(12 * f / 4) + 1)).resize((n, n), Image.BILINEAR)
    hole = Image.new("L", (n, n), 255)
    ImageDraw.Draw(hole).ellipse((c - rc * 0.99, c - rc * 0.99, c + rc * 0.99, c + rc * 0.99), fill=0)
    inner = ImageChops.multiply(inner, hole)
    room = np.asarray(inner.filter(ImageFilter.GaussianBlur(2 * f)), np.float32) / 255

    def free(x, y):
        return inner.getpixel((int(x), int(y))) if 0 <= x < n and 0 <= y < n else 0
    ys, xs = np.mgrid[0:n, 0:n].astype(np.float32)
    rho = np.hypot(xs - c, ys - c)
    theta = np.arctan2(ys - c, xs - c)

    def streaks(count, blur, seed, wiggle):
        v = np.random.default_rng(seed).random(count)
        kernel = np.exp(-0.5 * (np.arange(-3 * blur, 3 * blur + 1) / blur) ** 2)
        kernel /= kernel.sum()
        pad = len(kernel)
        v = np.convolve(np.concatenate([v[-pad:], v, v[:pad]]), kernel, "same")[pad:-pad]
        v = (v - v.min()) / (v.max() - v.min())
        s = rho / f
        t = theta + wiggle * (np.sin(s * 0.03 + theta * 37 + seed) + 0.6 * np.sin(s * 0.075 + theta * 91 + 2 * seed)
                              + 0.4 * np.sin(s * 0.16 + theta * 13))
        i = ((t / (2 * np.pi)) % 1) * count
        lo, part = i.astype(int) % count, i - np.floor(i)
        return v[lo] * (1 - part) + v[(lo + 1) % count] * part
    reach = (np.clip((rho - rc * 0.99) / (rc * 0.03), 0, 1)
             * np.clip(1 - (rho - rc) / (rc * 0.75), 0, 1) ** 1.3)
    field = 0.6 * streaks(2600, 1.1, 3, 0.007) + 0.4 * streaks(700, 1.5, 5, 0.012)
    fibers = (field - field.mean()) / field.std() * reach * room
    # (Vessels: smooth winding paths, each bend easing into the next, drawn as tapered
    # strips at twice the size.)
    rng = random.Random(15)
    S = 2
    body, core = Image.new("L", (n * S, n * S), 0), Image.new("L", (n * S, n * S), 0)
    draws = (ImageDraw.Draw(body), ImageDraw.Draw(core))

    def strip(draw, points, widths, scale):
        for (x0, y0), (x1, y1), w0, w1 in zip(points, points[1:], widths, widths[1:]):
            side = math.atan2(y1 - y0, x1 - x0) + math.pi / 2
            cs, sn = math.cos(side), math.sin(side)
            h0, h1 = w0 * scale / 2, w1 * scale / 2
            draw.polygon([((x0 + cs * h0) * S, (y0 + sn * h0) * S), ((x1 + cs * h1) * S, (y1 + sn * h1) * S),
                          ((x1 - cs * h1) * S, (y1 - sn * h1) * S), ((x0 - cs * h0) * S, (y0 - sn * h0) * S)],
                         fill=255)
            draw.ellipse(((x1 - h1) * S, (y1 - h1) * S, (x1 + h1) * S, (y1 + h1) * S), fill=255)

    def grow(x, y, heading, width, length, depth):
        points, widths = [(x, y)], [width]
        curve = rng.uniform(-0.05, 0.05)
        steps = max(6, int(length / (2 * f)))
        for step in range(steps):
            near = min(1, max(0, (math.hypot(x - c, y - c) - rc) / (rc * 0.12)))
            left = (1 - step / steps) * near
            if left < 0.04:
                break
            curve = max(-0.14, min(0.14, curve * 0.9 + rng.uniform(-0.05, 0.05)))
            toward = math.atan2(c - y, c - x)
            heading += curve + math.atan2(math.sin(toward - heading), math.cos(toward - heading)) * 0.015
            nx, ny = x + 2 * f * math.cos(heading), y + 2 * f * math.sin(heading)
            if free(nx, ny) < 90:
                break
            x, y = nx, ny
            points.append((x, y))
            widths.append(max(0.5 * f, width * left ** 0.75))
            if depth < 3 and step > 5 and rng.random() < 0.075:
                grow(x, y, heading + rng.choice((-1, 1)) * rng.uniform(0.4, 0.8), widths[-1] * 0.7,
                     length * left * 0.6, depth + 1)
        if len(points) > 2:
            strip(draws[0], points, widths, 1.0)
            strip(draws[1], points, widths, 0.4)
    for out in (-1, 1):
        base = math.pi if out < 0 else 0
        for i in range(9):
            t = base + (-1 + i / 4) * 1.1 + rng.uniform(-0.1, 0.1)
            for dist in range(int(a), int(rc), -2):
                x, y = c + dist * math.cos(t), c + dist * math.sin(t)
                if free(x, y) > 200:
                    break
            else:
                continue
            grow(x, y, math.atan2(c - y, c - x) + rng.choice((-1, 1)) * rng.uniform(0.7, 1.1),
                 rng.uniform(3, 4.2) * f, rng.uniform(110, 210) * f, 0)
    got = []
    for im in (body, core):
        im = im.filter(ImageFilter.GaussianBlur(0.8 * S * f)).resize((n, n), Image.LANCZOS)
        got.append(np.asarray(ImageChops.multiply(im, shape), np.float32) / 255)
    halo = Image.fromarray(np.uint8(got[0] * 255)).filter(ImageFilter.GaussianBlur(4 * f))
    return fibers, got[0], got[1], np.asarray(halo, np.float32) / 255, room


def eye_back():
    """Void Whisper's eye: behind a circle portrait, wider than it, a point out to each
    side and a dark upper lid. The circle is 1/1.75 of it across (EYE_SPAN in
    UnitStyle.lua). Grey, tinted to the ring's color; its shadow black. Shaded as a
    lid: lighter round the circle, dark toward its points, the upper lid's shadow
    falling in and a little light on the lower rim; grit. In it fine fibers reach out
    from the circle and a few dark vessels wind in from the edge (eye_iris), with a
    soft gloss up top.
    PortraitBackEyeVeins.tga: the vessels and the fibers by the circle, white, for
    their glow in fights and at low health.
    PortraitBackEyeMask.tga: its shape, for the mist drifting in it.
    PortraitBackEyeMist.tga: the mist, 128x128, wisps that tile."""
    n = 256 * 4
    c, d = n / 2, n / 1.75
    a, b = d * 1.575 / 2, d * 1.1 / 2
    k = d / 328  # (the mockup's scale: its numbers below)
    r = (a * a + b * b) / (2 * b)
    reach = math.asin(a / r)
    top = [(c + r * math.sin(t), c - (b - r + r * math.cos(t)))
           for t in (-reach + i * 2 * reach / 96 for i in range(97))]
    outline = top + [(x, 2 * c - y) for x, y in reversed(top)]
    shape = Image.new("L", (n, n), 0)
    ImageDraw.Draw(shape).polygon(outline, fill=255)
    save(shape.resize((256, 256), Image.LANCZOS), "PortraitBackEyeMask")
    # (Toward its points: by how far across from the middle.)
    body = Image.new("L", (n, n))
    body.putdata([int(175 - 150 * min(1, max(0, (abs(x - c) / a - 0.5) / 0.5)) ** 0.7)
                  for y in range(n) for x in range(n)])
    outside = ImageChops.invert(shape)
    fall = ImageChops.offset(outside, 0, round(14 * k)).filter(ImageFilter.GaussianBlur(16 * k))
    body = ImageChops.subtract(body, fall.point(lambda v: v * 170 // 255))
    rim = ImageChops.offset(outside, 0, -round(6 * k)).filter(ImageFilter.GaussianBlur(4 * k))
    low = Image.new("L", (n, n), 0)
    ImageDraw.Draw(low).rectangle((0, c + d * 0.1, n, n), fill=255)
    body = ImageChops.add(body, ImageChops.multiply(rim, low).point(lambda v: v * 70 // 255))
    patches = noise((n // 4, n // 4), 21, 3).resize((n, n), Image.BICUBIC).point(lambda v: max(0, v - 110) * 2)
    fine = noise((n, n), 11, 1.2 * k).point(lambda v: max(0, v - 140) * 2)
    body = ImageChops.subtract(body, ImageChops.multiply(fine, patches).point(lambda v: v * 60 // 255))
    # (Fibers, vessels and gloss: what's in it.)
    import numpy as np
    fibers, vessels, cores, halo, room = eye_iris(n, c, d, a, shape)
    rc = d / 2
    ys, xs = np.mgrid[0:n, 0:n].astype(np.float32)
    gloss = np.exp(-(((xs - (c - rc * 1.05)) / (rc * 0.55)) ** 2 + ((ys - (c - rc * 0.62)) / (rc * 0.28)) ** 2)) * room
    spot = np.exp(-(((xs - (c - rc * 1.2)) / (rc * 0.09)) ** 2 + ((ys - (c - rc * 0.5)) / (rc * 0.06)) ** 2)) * room
    light = np.clip((fibers - 0.3) * 0.32, 0, 1)
    grey = np.asarray(body, np.float32)
    grey *= 1 - 0.55 * np.clip(-fibers * 0.3, 0, 1)
    grey += 150 * 0.35 * light
    grey = grey * (1 - 0.6 * vessels) + 30 * 0.6 * vessels
    grey += 45 * 0.3 * cores
    grey += 150 * 0.22 * gloss + 240 * 0.6 * spot
    body = Image.fromarray(np.uint8(np.clip(grey, 0, 255)))
    # (The glow: the vessels, their core brighter, a soft halo; the light fibers, most by the circle.)
    near = np.clip(1 - (np.hypot(xs - c, ys - c) - rc * 0.99) / (rc * 0.28), 0, 1) ** 2 * room
    glow = np.maximum.reduce([vessels * 0.8, cores, halo * 0.55, light * (0.5 + near)])
    white(Image.fromarray(np.uint8(np.clip(glow, 0, 1) * 255)).resize((256, 256), Image.LANCZOS)).save(
        os.path.join(OUT, "PortraitBackEyeVeins.tga"), compression=None)
    lid = Image.new("L", (n, n), 0)
    ImageDraw.Draw(lid).line(top, fill=255, width=round(15 * k), joint="curve")
    lid = lid.filter(ImageFilter.GaussianBlur(2 * k))
    # (Its edge as the portrait rings have theirs: a band as thick as theirs on screen,
    # worn metal, raised and cracked, with a thin dark line just outside it.)
    band = Image.new("L", (n, n), 0)
    ImageDraw.Draw(band).line(outline + [outline[0]], fill=255, width=round(0.08 * d), joint="curve")
    band = ImageChops.multiply(band, shape)
    rim_line = Image.new("L", (n, n), 0)
    ImageDraw.Draw(rim_line).line(outline + [outline[0]], fill=255, width=22, joint="curve")
    black, clear = Image.new("L", (n, n), 0), Image.new("RGBA", (n, n), (0, 0, 0, 0))

    def layer(grey, alpha):
        g = grey if isinstance(grey, Image.Image) else Image.new("L", (n, n), grey)
        return Image.merge("RGBA", (g, g, g, alpha))
    out = Image.alpha_composite(clear, layer(black, shape.filter(ImageFilter.GaussianBlur(18)).point(lambda v: v * 110 // 255)))
    out = Image.alpha_composite(out, layer(body, shape.point(lambda v: v * 215 // 255)))
    out = Image.alpha_composite(out, layer(10, lid))
    out = Image.alpha_composite(out, layer(black, rim_line.point(lambda v: v * 190 // 255)))
    out = out.resize((256, 256), Image.LANCZOS)
    out = Image.alpha_composite(out, worn(band.resize((256, 256), Image.LANCZOS), sum(ord(ch) for ch in "Eye")))
    out.save(os.path.join(OUT, "PortraitBackEye.tga"), compression=None)
    # (Mist: soft wisps that meet themselves at every edge, so it can drift for ever.)
    m = 128
    rng = random.Random(31)
    seeds = Image.new("L", (m, m))
    seeds.putdata([rng.randrange(256) for _ in range(m * m)])
    big = Image.new("L", (m * 3, m * 3))
    for tx in range(3):
        for ty in range(3):
            big.paste(seeds, (tx * m, ty * m))
    wisps = big.filter(ImageFilter.GaussianBlur(7)).crop((m, m, 2 * m, 2 * m))
    lo, hi = wisps.getextrema()
    wisps = wisps.point(lambda v: min(255, max(0, (v - lo) * 255 // max(1, hi - lo) - 110) * 2))
    white(wisps).save(os.path.join(OUT, "PortraitBackEyeMist.tga"), compression=None)


def cracked(alpha, seed, grain=1):
    """Hairline cracks and small nicks scattered round a ring, a different scatter for each
    shape: gives what to multiply its tone by, and its alpha with the nicks taken out."""
    w, h = alpha.size
    rng = random.Random(seed)
    on_ring = [(x, y) for y in range(h) for x in range(w) if alpha.getpixel((x, y)) > 200]
    tone = Image.new("L", (w * 4, h * 4), 255)
    d = ImageDraw.Draw(tone)
    for _ in range(rng.randrange(13, 19)):
        x, y = rng.choice(on_ring)
        heading = rng.uniform(0, 2 * math.pi)
        points = [(x * 4, y * 4)]
        for _ in range(rng.randrange(3, 7)):
            heading += rng.uniform(-0.9, 0.9)
            step = rng.uniform(4, 9) * grain
            points.append((points[-1][0] + step * math.cos(heading), points[-1][1] + step * math.sin(heading)))
        d.line(points, fill=rng.randrange(70, 130), width=rng.choice((2, 3, 3, 4)) * grain)
    tone = tone.resize((w, h), Image.LANCZOS)
    nicks = Image.new("L", (w * 4, h * 4), 255)
    d = ImageDraw.Draw(nicks)
    for _ in range(rng.randrange(6, 10)):
        x, y = rng.choice(on_ring)
        r = rng.uniform(2.5, 5) * grain
        d.ellipse((x * 4 - r, y * 4 - r, x * 4 + r, y * 4 + r), fill=rng.randrange(40, 130))
    return tone, ImageChops.multiply(alpha, nicks.resize((w, h), Image.LANCZOS))


def worn(alpha, seed=1, overhead=False, mottle=3, grain=1, clean=False):
    """A ring as worn metal: lit from the top left, shaded to the bottom right, mottled.
    Grey on its way to the theme's color, so wear shows in any of them. seed: where its
    cracks and nicks go; mottle: its blotches; grain: how big its wear is (2 for art
    drawn at twice a portrait's size, so it looks as rough); clean: no wear at all, just
    the light on it (the modern themes')."""
    w, h = alpha.size
    light = Image.new("L", (w, h))
    light.putdata([int(255 - 60 * (x + y) / (w + h)) for y in range(h) for x in range(w)])
    blotch = noise((w, h), mottle, 2.2 * grain).point(lambda v: 230 if clean else 205 + v * 50 // 255)
    grey = ImageChops.multiply(light, blotch).point(lambda v: v * 80 // 100)
    # (Raised along its middle: light from the top left falls on the slopes facing it, and
    # those facing away go dark, so the ring stands up from the frame.)
    height = alpha.filter(ImageFilter.GaussianBlur(1.6 * grain))
    # (overhead: a shape all on the diagonal, lit from above so its four sides match.)
    dx = 0 if overhead else grain
    up, down = ImageChops.offset(height, -dx, -grain), ImageChops.offset(height, dx, grain)
    grey = ImageChops.add(grey, ImageChops.subtract(up, down).point(lambda v: min(255, v * 9 // 10)))
    grey = ImageChops.subtract(grey, ImageChops.subtract(down, up).point(lambda v: min(255, v * 11 // 10)))
    # (Never near black: its dark slope would vanish, and that side look thinner.)
    grey = grey.point(lambda v: max(v, 100))
    if not clean:
        tone, alpha = cracked(alpha, seed, grain)
        grey = ImageChops.multiply(grey, tone)
    return Image.merge("RGBA", (grey, grey, grey, alpha))


def shade(cut_alpha):
    """Dark just inside a shape's edge: sets the picture back into its ring."""
    outside = ImageChops.invert(cut_alpha).filter(ImageFilter.GaussianBlur(7))
    edge = ImageChops.multiply(outside, cut_alpha).point(lambda v: min(255, v * 2))
    black = Image.new("L", cut_alpha.size, 0)
    return Image.merge("RGBA", (black, black, black, edge))


def grit():
    """Dirt to lay over flat fills: in patches, with bare stretches between, as dirt
    gathers. Bigger than any bar, which each shows a patch of its own (UnitStyle.lua)."""
    size = (512, 128)
    patches = noise(size, 21, 16).point(lambda v: max(0, v - 118) * 3)
    fine = noise(size, 11, 0.7).point(lambda v: max(0, v - 138) * 3)
    specks = ImageChops.multiply(fine, patches)
    smudge = ImageChops.multiply(noise(size, 12, 9).point(lambda v: max(0, v - 130)), patches)
    dirt = ImageChops.add(specks, smudge)
    d = ImageDraw.Draw(dirt)
    rng = random.Random(13)
    for _ in range(14):
        x, y = rng.randrange(512), rng.randrange(128)
        reach = rng.randrange(6, 26)
        d.line([(x, y), (x + reach, y + rng.randrange(-3, 4))], fill=rng.randrange(50, 100))
    black = Image.new("L", size, 0)
    Image.merge("RGBA", (black, black, black, dirt)).save(os.path.join(OUT, "Grit.tga"), compression=None)


def sheen():
    """Light over a flat bar: bright along the top, falling to shade along the bottom,
    darker toward both ends. One RGBA picture, white where it lights, black where it shades."""
    w, h = 256, 64
    grey, alpha = Image.new("L", (w, h)), Image.new("L", (w, h))
    tones, strengths = [], []
    for y in range(h):
        t = y / (h - 1)
        for x in range(w):
            edge = abs(x / (w - 1) - 0.5) * 2
            dark = 0.46 * max(0, (t - 0.42) / 0.58) ** 1.3 + 0.16 * edge ** 3
            light = 0.12 * max(0, 1 - t / 0.42) ** 1.5
            tones.append(255 if light > dark else 0)
            # (Their difference: nothing where they meet, or that line shows as a curve.)
            strengths.append(int(255 * abs(light - dark)))
    grey.putdata(tones)
    alpha.putdata(strengths)
    Image.merge("RGBA", (grey, grey, grey, alpha)).save(os.path.join(OUT, "Sheen.tga"), compression=None)


def collar():
    """Shading over the connector between a portrait and its rows, 32x96: black falling
    away from the portrait and in from its top and bottom, so its middle stands lightest,
    with a little wear. Its fill and lines are the rows' own."""
    w, h = 32, 96
    wear = noise((w, h), 41, 1.8)
    data = []
    for y in range(h):
        t = abs(y / (h - 1) - 0.5) * 2
        for x in range(w):
            across = 0.72 * (1 - x / (w - 1)) ** 1.5
            down = 0.66 * max(0, (t - 0.45) / 0.55) ** 1.6
            dark = 1 - (1 - across) * (1 - down) * (1 - 0.1)
            data.append(max(0, min(255, int(255 * dark + (wear.getpixel((x, y)) - 128) * 0.2))))
    a = Image.new("L", (w, h))
    a.putdata(data)
    black = Image.new("L", (w, h), 0)
    Image.merge("RGBA", (black, black, black, a)).save(os.path.join(OUT, "Collar.tga"), compression=None)
    # (A cell's corner, top left: metal cut across at 45 degrees, tinted to the frame,
    # with a dark line along the cut.)
    n = 24
    big = Image.new("L", (n * SS, n * SS), 0)
    ImageDraw.Draw(big).polygon([(0, 0), (n * SS, 0), (0, n * SS)], fill=255)
    tone = Image.new("L", (n * SS, n * SS), 255)
    ImageDraw.Draw(tone).line([(n * SS, 0), (0, n * SS)], fill=0, width=7 * SS)
    alpha = ImageChops.lighter(big, ImageChops.invert(tone))
    g = tone.resize((n, n), Image.LANCZOS)
    Image.merge("RGBA", (g, g, g, alpha.resize((n, n), Image.LANCZOS))).save(os.path.join(OUT, "CellCorner.tga"), compression=None)


def frame_shadow():
    """A soft dark edge to lay behind a frame's rows, 128x64."""
    big = Image.new("L", (128, 64), 0)
    ImageDraw.Draw(big).rectangle((10, 10, 118, 54), fill=255)
    soft = big.filter(ImageFilter.GaussianBlur(4)).point(lambda v: v * 170 // 255)
    black = Image.new("L", (128, 64), 0)
    Image.merge("RGBA", (black, black, black, soft)).save(os.path.join(OUT, "RowShadow.tga"), compression=None)


def fill(name, grey):
    """A bar fill in ../Bars: grey over white, the bar's color tints it. Opaque."""
    w, h = grey.size
    Image.merge("RGBA", (grey, grey, grey, Image.new("L", (w, h), 255))).save(
        os.path.join(ROOT, "Textures", "Bars", name + ".tga"), compression=None)


def ramp(size, top, bottom):
    """Top to bottom, from one level of grey to another."""
    w, h = size
    im = Image.new("L", size)
    im.putdata([int(top + (bottom - top) * y / (h - 1)) for y in range(h) for _ in range(w)])
    return im


def mix(base, texture, low):
    """base darkened by texture, from low (0 to 1) of itself where texture's black."""
    return ImageChops.multiply(base, texture.point(lambda v: int(255 * low + v * (1 - low))))


def bars():
    size = (256, 32)
    base = ramp(size, 255, 226)
    # (Long fine strokes along the bar, as on rubbed metal.)
    rng = random.Random(31)
    streaks = Image.new("L", size)
    streaks.putdata([v for v in (rng.randrange(256) for _ in range(32)) for _ in range(256)])
    long = noise(size, 32, 1).resize((1024, 32)).crop((0, 0, 256, 32))
    fill("Brushed", mix(mix(base, streaks, 0.86), long, 0.9))
    # (Blotches of wear, darker at the edges.)
    worn = noise(size, 33, 5)
    edges = ImageChops.multiply(ramp(size, 215, 255), ramp(size, 255, 205))
    fill("Worn", mix(mix(ImageChops.multiply(base, edges), worn, 0.84), noise(size, 34, 0.7), 0.94))
    # (A fine weave.)
    weave = Image.new("L", size)
    weave.putdata([255 if (x % 3 == 0) != (y % 3 == 0) else 190 for y in range(32) for x in range(256)])
    fill("Linen", mix(base, weave, 0.86))
    # (Smooth, full, with one soft band of light: cloth or lacquer.)
    satin = Image.new("L", size)
    satin.putdata([int(214 + 41 * math.sin(math.pi * min(1, y / 22)) ** 2) for y in range(32) for _ in range(256)])
    fill("Satin", satin)
    # (Dents from a hammer.)
    dents = noise(size, 35, 2.4).point(lambda v: 255 if v > 120 else 150 + v * 105 // 120)
    fill("Hammered", mix(base, dents.filter(ImageFilter.GaussianBlur(0.8)), 0.76))


def cut(big):
    # (The shape at 7/8, centered: what shows inside its ring, the mask being over
    # the portrait's whole place.)
    small = big.resize((112, 112), Image.LANCZOS)
    out = Image.new("L", (128, 128), 0)
    out.paste(small, (8, 8))
    return out


def hole(big, name):
    """White with the shape, a touch smaller, clear in its middle: for a mask twice the
    portrait's size, which keeps what's under it out of the picture."""
    small = big.resize((60, 60), Image.LANCZOS)
    out = Image.new("L", (128, 128), 0)
    out.paste(small, (34, 34))
    save(ImageChops.invert(out), "Portrait" + name + "Out")


RING_WEARS = 4


def finish(big, name):
    ring = even_outline(big, 5).resize((128, 128), Image.LANCZOS)
    seed = sum(ord(c) for c in name)
    worn(ring, seed, name == "Diamond").save(os.path.join(OUT, "Portrait" + name + "Ring.tga"), compression=None)
    ring_wears(ring, name)
    save(cut(big), "Portrait" + name + "Cut")
    shade(cut(big)).save(os.path.join(OUT, "Portrait" + name + "Shade.tga"), compression=None)
    hole(big, name)


def ring_wears(ring, name):
    """Portrait<Name>Ring2 to 4: the ring worn other ways."""
    seed = sum(ord(c) for c in name)
    for wear in range(2, RING_WEARS + 1):
        worn(ring, seed + 977 * wear, name == "Diamond", 3 + 11 * wear).save(
            os.path.join(OUT, "Portrait" + name + "Ring" + str(wear) + ".tga"), compression=None)


MINIMAP_OUTER, MINIMAP_WIDTH = 124, 10  # (of 128: where the shade's circle comes from)
MINIMAP_INNER = (MINIMAP_OUTER - MINIMAP_WIDTH) / 128


def frame_mask():
    """SquareFrameMask.tga: a square button's frame and none of its middle, 64x64,
    white on clear (the frame FRAME_BAND of its size thick): for a tinted copy of a
    button's art that colors its frame alone (the minimap's calendar)."""
    n = 64
    band = round(n * FRAME_BAND) * SS
    big = Image.new("L", (n * SS, n * SS), 255)
    ImageDraw.Draw(big).rounded_rectangle((band, band, n * SS - band, n * SS - band), radius=2 * SS, fill=0)
    save(big.resize((n, n), Image.LANCZOS), "SquareFrameMask")


FRAME_BAND = 0.17


def minimap():
    frame_mask()
    n = 256
    c = n * SS / 2
    inside = Image.new("L", (n * SS, n * SS), 0)
    r = MINIMAP_INNER * n * SS / 2
    ImageDraw.Draw(inside).ellipse((c - r, c - r, c + r, c + r), fill=255)
    shade(inside.resize((n, n), Image.LANCZOS)).save(os.path.join(OUT, "MinimapRimShade.tga"), compression=None)


def portraits():
    for name, draw in PORTRAITS.items():
        big = Image.new("L", (128 * SS, 128 * SS), 0)
        draw(ImageDraw.Draw(big), SS)
        save(big.resize((128, 128), Image.LANCZOS), "Portrait" + name)
        finish(big, name)
    big = Image.new("L", (128 * SS, 128 * SS), 0)
    ImageDraw.Draw(big).ellipse((2 * SS, 2 * SS, 126 * SS, 126 * SS), fill=255)
    finish(big, "Circle")
    big = Image.new("L", (128 * SS, 128 * SS), 255)
    hole(big, "Square")


def main():
    grit()
    sheen()
    collar()
    frame_shadow()
    eye_back()
    bars()
    panels()
    tail()
    for name, draw in (("Capsule", bar_capsule),
                       ("Chisel", bar_chisel),
                       ("Soft", bar_soft), ("Bevel", bar_bevel)):
        # (Clear at both ends: past its own edges a mask repeats them, so a bar wider
        # than the shape would carry its last column on.)
        out = Image.new("L", (256, 32), 0)
        out.paste(stamp((256, 32), draw).resize((248, 32), Image.LANCZOS), (4, 0))
        save(out, "Bar" + name)
    portraits()
    minimap()


if __name__ == "__main__":
    main()
