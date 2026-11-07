"""The shapes the style themes can give panels, bars and portraits (StyleThemes.lua),
drawn from scratch here. Usage, from the repo root: python Media/make_shape_art.py

Textures/Themes/Shapes/:
Panel<Name>.tga and Panel<Name>Edge.tga: a panel's fill and its line, 128x128, white
on clear, drawn as nine pieces whose corners are a quarter each (ns.DressThemeSlice);
twice the size they're drawn at, so a corner stays smooth at any UI scale.
Tail.tga and TailEdge.tga: a chat bubble's tail and the line down its sides, 128x128.
Bar<Name>.tga: a mask for a bar, 256x32, white on clear: what's clear is cut away.
Portrait<Name>.tga and Portrait<Name>Ring.tga: a portrait's mask and the line
round it, 128x128, white on clear. Portrait<Name>Cut.tga: what cuts the real one.
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


def eye_back():
    """Void Whisper's eye: behind a circle portrait, wider than it, a point out to each
    side and a dark upper lid. The circle is 1/1.75 of it across (EYE_SPAN in
    UnitStyle.lua). Grey, tinted to the ring's color; its shadow black. Shaded as a
    lid: lighter round the circle, dark toward its points, the upper lid's shadow
    falling in and a little light on the lower rim; grit and hairline cracks.
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
    rng = random.Random(7)
    cracks = Image.new("L", (n, n), 0)
    draw = ImageDraw.Draw(cracks)
    room = [(x, y) for y in range(0, n, 6) for x in range(0, n, 6)
            if shape.getpixel((x, y)) > 200 and math.hypot(x - c, y - c) > d / 2]
    for _ in range(9):
        x, y = rng.choice(room)
        heading = rng.uniform(0, 2 * math.pi)
        points = [(x, y)]
        for _ in range(rng.randrange(3, 6)):
            heading += rng.uniform(-0.8, 0.8)
            step = rng.uniform(8, 16) * k
            points.append((points[-1][0] + step * math.cos(heading), points[-1][1] + step * math.sin(heading)))
        draw.line(points, fill=rng.randrange(120, 200), width=round(2 * k))
    body = ImageChops.subtract(body, cracks.filter(ImageFilter.GaussianBlur(0.6 * k)).point(lambda v: v * 100 // 255))
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


def cracked(alpha, seed):
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
            step = rng.uniform(4, 9)
            points.append((points[-1][0] + step * math.cos(heading), points[-1][1] + step * math.sin(heading)))
        d.line(points, fill=rng.randrange(70, 130), width=rng.choice((2, 3, 3, 4)))
    tone = tone.resize((w, h), Image.LANCZOS)
    nicks = Image.new("L", (w * 4, h * 4), 255)
    d = ImageDraw.Draw(nicks)
    for _ in range(rng.randrange(6, 10)):
        x, y = rng.choice(on_ring)
        r = rng.uniform(2.5, 5)
        d.ellipse((x * 4 - r, y * 4 - r, x * 4 + r, y * 4 + r), fill=rng.randrange(40, 130))
    return tone, ImageChops.multiply(alpha, nicks.resize((w, h), Image.LANCZOS))


def worn(alpha, seed=1, overhead=False):
    """A ring as worn metal: lit from the top left, shaded to the bottom right, mottled.
    Grey on its way to the theme's color, so wear shows in any of them."""
    w, h = alpha.size
    light = Image.new("L", (w, h))
    light.putdata([int(255 - 60 * (x + y) / (w + h)) for y in range(h) for x in range(w)])
    blotch = noise((w, h), 3, 2.2).point(lambda v: 205 + v * 50 // 255)
    grey = ImageChops.multiply(light, blotch).point(lambda v: v * 80 // 100)
    # (Raised along its middle: light from the top left falls on the slopes facing it, and
    # those facing away go dark, so the ring stands up from the frame.)
    height = alpha.filter(ImageFilter.GaussianBlur(1.6))
    # (overhead: a shape all on the diagonal, lit from above so its four sides match.)
    dx = 0 if overhead else 1
    up, down = ImageChops.offset(height, -dx, -1), ImageChops.offset(height, dx, 1)
    grey = ImageChops.add(grey, ImageChops.subtract(up, down).point(lambda v: min(255, v * 9 // 10)))
    grey = ImageChops.subtract(grey, ImageChops.subtract(down, up).point(lambda v: min(255, v * 11 // 10)))
    # (Never near black: its dark slope would vanish, and that side look thinner.)
    grey = grey.point(lambda v: max(v, 100))
    tone, alpha = cracked(alpha, seed)
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


def finish(big, name):
    ring = even_outline(big, 5).resize((128, 128), Image.LANCZOS)
    worn(ring, sum(ord(c) for c in name), name == "Diamond").save(os.path.join(OUT, "Portrait" + name + "Ring.tga"), compression=None)
    save(cut(big), "Portrait" + name + "Cut")
    shade(cut(big)).save(os.path.join(OUT, "Portrait" + name + "Shade.tga"), compression=None)
    hole(big, name)


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


if __name__ == "__main__":
    main()
