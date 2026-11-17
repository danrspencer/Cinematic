"""Icon for the links to a frame's Style page (StylePages.lua's ns.StyleIcon):
64x64, a flat cream artist's palette on a see-through background, its thumb
hole, notch and paint wells cut out. Our own, drawn from scratch here; usage:
make_style_palette.py Textures/StylePalette.tga"""
import sys
from PIL import Image, ImageDraw

N = 64
S = 4  # drawn this many times bigger, then shrunk, for smooth edges
OUT = sys.argv[1] if len(sys.argv) > 1 else "StylePalette.tga"
CREAM = (246, 236, 212, 255)
CLEAR = (0, 0, 0, 0)

big = Image.new("RGBA", (N * S, N * S), CLEAR)
draw = ImageDraw.Draw(big)


def circle(x, y, r, fill):
    draw.ellipse([(x - r) * S, (y - r) * S, (x + r) * S, (y + r) * S], fill=fill)


# The palette, then what's cut out of it: the notch bottom right, the thumb
# hole above it, and four paint wells round the far edge.
draw.ellipse([6 * S, 10 * S, 58 * S, 54 * S], fill=CREAM)
draw.ellipse([34 * S, 38 * S, 62 * S, 62 * S], fill=CLEAR)
circle(42, 32, 4, CLEAR)
for x, y in ((18, 20), (31, 16), (15, 33), (24, 44)):
    circle(x, y, 4.5, CLEAR)

big.resize((N, N), Image.LANCZOS).save(OUT)
