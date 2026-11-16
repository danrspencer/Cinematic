"""A 128x128 quest "!" icon in the game's spell-icon style: a dark warm
ground with a soft light behind, a gold "!" with a dark edge and a lit top."""
import math
import sys
from PIL import Image, ImageDraw, ImageFilter

S = 4  # supersampling
W = 128 * S
out = sys.argv[1]

# Ground: dark brown, lighter toward the middle-top, darker at the edges.
ground = Image.new("RGBA", (W, W))
px = ground.load()
for y in range(W):
    for x in range(W):
        dx, dy = (x - W * 0.5) / W, (y - W * 0.42) / W
        d = math.sqrt(dx * dx + dy * dy)
        t = max(0.0, 1.0 - d * 1.6)
        r = int(28 + 70 * t)
        g = int(18 + 44 * t)
        b = int(10 + 16 * t)
        px[x, y] = (r, g, b, 255)

def bang(draw, fill, grow=0):
    g = grow * S
    # the bar: wider at the top, rounded ends
    top, bottom = 18 * S, 82 * S
    draw.polygon([(W / 2 - 15 * S - g, top - g), (W / 2 + 15 * S + g, top - g),
                  (W / 2 + 8 * S + g, bottom + g), (W / 2 - 8 * S - g, bottom + g)], fill=fill)
    draw.ellipse([W / 2 - 15 * S - g, top - 9 * S - g, W / 2 + 15 * S + g, top + 9 * S + g], fill=fill)
    draw.ellipse([W / 2 - 8 * S - g, bottom - 8 * S - g, W / 2 + 8 * S + g, bottom + 8 * S + g], fill=fill)
    # the dot
    draw.ellipse([W / 2 - 11 * S - g, 94 * S - g, W / 2 + 11 * S + g, 116 * S + g], fill=fill)

# A glow behind it.
glow = Image.new("L", (W, W), 0)
bang(ImageDraw.Draw(glow), 255, grow=8)
glow = glow.filter(ImageFilter.GaussianBlur(10 * S))
ground.paste(Image.new("RGBA", (W, W), (255, 190, 40, 255)), (0, 0), glow.point(lambda v: int(v * 0.55)))

# The dark edge.
edge = Image.new("L", (W, W), 0)
bang(ImageDraw.Draw(edge), 255, grow=3)
ground.paste(Image.new("RGBA", (W, W), (40, 20, 0, 255)), (0, 0), edge)

# The gold, light at the top going to deep amber at the bottom, lit down its left.
mask = Image.new("L", (W, W), 0)
bang(ImageDraw.Draw(mask), 255)
gold = Image.new("RGBA", (W, W))
gp = gold.load()
for y in range(W):
    t = y / W
    for x in range(W):
        side = max(0.0, 1.0 - abs((x - (W / 2 - 4 * S)) / (10 * S)))
        r = min(255, int(255))
        g = min(255, int(236 - 90 * t + 30 * side))
        b = min(255, int(120 - 110 * t + 60 * side))
        gp[x, y] = (r, g, max(0, b), 255)
ground.paste(gold, (0, 0), mask)

# A dark rim round the square, as the game's icons have.
draw = ImageDraw.Draw(ground)
for i in range(3 * S):
    a = int(160 * (1 - i / (3 * S)))
    draw.rectangle([i, i, W - 1 - i, W - 1 - i], outline=(0, 0, 0, a))

ground = ground.resize((128, 128), Image.LANCZOS)
ground.save(out)
ground.save(out.replace(".tga", "_preview.png"))
print("ok")
