"""A 128x128 personal resource display icon in the game's spell-icon style
(the Personal Resources icons, Interface and Style hubs, 2026-11-17): a dark
ground with a soft light behind, a health bar over a mana bar (each in a dark
frame, its fill lit along the top, part empty), and a row of five combo points
under them, three lit. Bars are straight, end to end: only their ends rounded.

    python Media/make_prd_icon.py Textures/PersonalResources.tga
"""
import math
import sys
from PIL import Image, ImageDraw, ImageFilter

S = 4  # supersampling
W = 128 * S
out = sys.argv[1]

# Ground: dark blue-grey, lighter toward the middle, darker at the edges.
ground = Image.new("RGBA", (W, W))
px = ground.load()
for y in range(W):
    for x in range(W):
        dx, dy = (x - W * 0.5) / W, (y - W * 0.45) / W
        d = math.sqrt(dx * dx + dy * dy)
        t = max(0.0, 1.0 - d * 1.5)
        px[x, y] = (int(14 + 34 * t), int(16 + 38 * t), int(22 + 46 * t), 255)

LEFT, RIGHT = 16 * S, 112 * S
BARS = [
    # top, height, fill share, dark color, light color
    (28 * S, 26 * S, 0.78, (20, 120, 20), (120, 235, 90)),   # health
    (62 * S, 20 * S, 0.56, (14, 50, 150), (90, 160, 255)),   # mana
]


def bar_shape(draw, top, height, fill, grow=0):
    g = grow * S
    draw.rounded_rectangle([LEFT - g, top - g, RIGHT + g, top + height + g], radius=height // 3 + g, fill=fill)


# A glow behind the bars.
glow = Image.new("L", (W, W), 0)
gd = ImageDraw.Draw(glow)
for top, height, *_ in BARS:
    bar_shape(gd, top, height, 255, grow=6)
glow = glow.filter(ImageFilter.GaussianBlur(9 * S))
ground.paste(Image.new("RGBA", (W, W), (120, 170, 255, 255)), (0, 0), glow.point(lambda v: int(v * 0.35)))

draw = ImageDraw.Draw(ground)
for top, height, share, dark, light in BARS:
    # Its frame: a dark edge, then the empty part's near-black.
    bar_shape(draw, top, height, (0, 0, 0, 255), grow=3)
    bar_shape(draw, top, height, (10, 10, 14, 255))
    # The fill, lit along its top, clipped to the bar and its share.
    mask = Image.new("L", (W, W), 0)
    bar_shape(ImageDraw.Draw(mask), top, height, 255)
    cut = ImageDraw.Draw(mask)
    cut.rectangle([LEFT + (RIGHT - LEFT) * share, 0, W, W], fill=0)
    fill = Image.new("RGBA", (W, W))
    fp = fill.load()
    for y in range(top, top + height + 1):
        t = (y - top) / height
        lit = max(0.0, 1.0 - t * 1.6)
        for x in range(LEFT, RIGHT + 1):
            fp[x, y] = tuple(int(d + (l - d) * lit) for d, l in zip(dark, light)) + (255,)
    ground.paste(fill, (0, 0), mask)
    # A thin shine just under the top edge.
    shine = Image.new("L", (W, W), 0)
    ImageDraw.Draw(shine).rectangle([LEFT + 6 * S, top + 3 * S, LEFT + (RIGHT - LEFT) * share - 4 * S,
                                     top + 5 * S], fill=110)
    ground.paste(Image.new("RGBA", (W, W), (255, 255, 255, 255)), (0, 0),
                 Image.composite(shine, Image.new("L", (W, W), 0), mask))

# Combo points: five, three lit gold.
for i in range(5):
    cx = W / 2 + (i - 2) * 19 * S
    cy = 102 * S
    r = 7 * S
    draw.ellipse([cx - r - 2 * S, cy - r - 2 * S, cx + r + 2 * S, cy + r + 2 * S], fill=(0, 0, 0, 255))
    if i < 3:
        draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(200, 120, 10, 255))
        draw.ellipse([cx - r * 0.6, cy - r * 0.75, cx + r * 0.4, cy + r * 0.1], fill=(255, 225, 120, 255))
    else:
        draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(40, 34, 30, 255))

# A dark rim round the square, as the game's icons have.
for i in range(3 * S):
    a = int(160 * (1 - i / (3 * S)))
    draw.rectangle([i, i, W - 1 - i, W - 1 - i], outline=(0, 0, 0, a))

ground = ground.resize((128, 128), Image.LANCZOS)
ground.save(out)
ground.save(out.replace(".tga", "_preview.png"))
print("ok")
