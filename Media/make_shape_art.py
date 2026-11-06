"""The shapes the style themes can give panels, bars and portraits (StyleThemes.lua),
drawn from scratch here. Usage, from the repo root: python Media/make_shape_art.py

Textures/Themes/Shapes/:
Panel<Name>.tga and Panel<Name>Edge.tga: a panel's fill and its line, 128x128, white
on clear, drawn as nine pieces whose corners are a quarter each (ns.DressThemeSlice);
twice the size they're drawn at, so a corner stays smooth at any UI scale.
NameShade.tga: a soft patch behind a unit frame's name, 128x32.
Tail.tga and TailEdge.tga: a chat bubble's tail and the line down its sides, 128x128.
Bar<Name>.tga: a mask for a bar, 256x32, white on clear: what's clear is cut away.
Portrait<Name>.tga and Portrait<Name>Ring.tga: a portrait's mask and the line
round it, 128x128, white on clear. Portrait<Name>Cut.tga: what cuts the real one.
"""
import math
import os

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


def poly(points):
    def draw(d, s):
        d.polygon([(x * s, y * s) for x, y in points], fill=255)
    return draw


# Panels: 64x64, the shape's corners inside the 16 pixel corner pieces.
def panel_round(d, s):
    d.rounded_rectangle((1 * s, 1 * s, 63 * s, 63 * s), radius=13 * s, fill=255)


def panel_chamfer(d, s):
    c = 11
    poly([(1 + c, 1), (63 - c, 1), (63, 1 + c), (63, 63 - c), (63 - c, 63), (1 + c, 63), (1, 63 - c), (1, 1 + c)])(d, s)


def panel_blade(d, s):
    c = 14
    poly([(1 + c, 1), (63, 1), (63, 63 - c), (63 - c, 63), (1, 63), (1, 1 + c)])(d, s)


def panel_notch(d, s):
    d.rectangle((1 * s, 1 * s, 63 * s, 63 * s), fill=255)
    r = 10
    for cx, cy in ((1, 1), (63, 1), (1, 63), (63, 63)):
        d.ellipse(((cx - r) * s, (cy - r) * s, (cx + r) * s, (cy + r) * s), fill=0)


def panel_sigil(d, s):
    # (Each corner pulled in to a point.)
    a, b = 15, 9
    poly([(1 + a, 1), (63 - a, 1), (63 - b, 1 + b), (63, 1 + a), (63, 63 - a), (63 - b, 63 - b), (63 - a, 63),
          (1 + a, 63), (1 + b, 63 - b), (1, 63 - a), (1, 1 + a), (1 + b, 1 + b)])(d, s)


def panel_veil(d, s):
    # (Soft above, sharp below.)
    d.rounded_rectangle((1 * s, 1 * s, 63 * s, 63 * s), radius=15 * s, fill=255, corners=(True, True, False, False))


PANELS = {"Round": panel_round, "Chamfer": panel_chamfer, "Blade": panel_blade, "Notch": panel_notch,
          "Sigil": panel_sigil, "Veil": panel_veil}


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


def bar_slant(d, s):
    poly([(14, 1), (256, 1), (242, 31), (0, 31)])(d, s)


def bar_point(d, s):
    poly([(0, 16), (12, 1), (244, 1), (256, 16), (244, 31), (12, 31)])(d, s)


def bar_barb(d, s):
    poly([(0, 1), (244, 1), (256, 16), (244, 31), (0, 31), (12, 16)])(d, s)


def bar_taper(d, s):
    poly([(0, 1), (256, 7), (256, 25), (0, 31)])(d, s)


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


PORTRAITS = {"Hex": poly(regular(6, math.pi / 6)), "Diamond": poly([(64, 2), (126, 64), (64, 126), (2, 64)]),
             "Arch": portrait_arch, "Eye": portrait_eye,
             "Shard": poly([(66, 2), (112, 30), (126, 78), (72, 126), (20, 106), (2, 44)])}


def cut(big):
    # (The shape at 7/8, centered: what shows inside its ring, the mask being over
    # the portrait's whole place.)
    small = big.resize((112, 112), Image.LANCZOS)
    out = Image.new("L", (128, 128), 0)
    out.paste(small, (8, 8))
    return out


def portraits():
    for name, draw in PORTRAITS.items():
        big = Image.new("L", (128 * SS, 128 * SS), 0)
        draw(ImageDraw.Draw(big), SS)
        save(big.resize((128, 128), Image.LANCZOS), "Portrait" + name)
        save(outline(big, 5).resize((128, 128), Image.LANCZOS), "Portrait" + name + "Ring")
        save(cut(big), "Portrait" + name + "Cut")
    big = Image.new("L", (128 * SS, 128 * SS), 0)
    ImageDraw.Draw(big).ellipse((2 * SS, 2 * SS, 126 * SS, 126 * SS), fill=255)
    save(cut(big), "PortraitCircleCut")


def name_shade():
    # (Soft on every side: it shouldn't read as a box.)
    big = Image.new("L", (128, 32), 0)
    ImageDraw.Draw(big).rounded_rectangle((14, 8, 114, 24), radius=8, fill=255)
    save(big.filter(ImageFilter.GaussianBlur(5)), "NameShade")


def main():
    panels()
    name_shade()
    tail()
    for name, draw in (("Capsule", bar_capsule), ("Slant", bar_slant), ("Point", bar_point),
                       ("Barb", bar_barb), ("Taper", bar_taper)):
        # (Clear at both ends: past its own edges a mask repeats them, so a bar wider
        # than the shape would carry its last column on.)
        out = Image.new("L", (256, 32), 0)
        out.paste(stamp((256, 32), draw).resize((248, 32), Image.LANCZOS), (4, 0))
        save(out, "Bar" + name)
    portraits()


if __name__ == "__main__":
    main()
