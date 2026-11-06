"""Icon for the grids' Back to the dropdowns button (GridRows.lua): 64x64, three
white rows on a see-through background, each a tick box and a line, a dark edge
for contrast. Our own, drawn from scratch here; usage:
make_grid_icon.py Textures/GridIcon.tga"""
import sys
from PIL import Image

N = 64
S = 4  # drawn this many times bigger, then shrunk, for smooth edges
OUT = sys.argv[1] if len(sys.argv) > 1 else "GridIcon.tga"
LIGHT, DARK = (246, 240, 226, 255), (40, 34, 28, 255)

big = Image.new("RGBA", (N * S, N * S), (0, 0, 0, 0))
for top in (6, 25, 44):
    for box in ((5, top, 19, top + 14), (25, top + 2, 59, top + 12)):
        x0, y0, x1, y1 = (v * S for v in box)
        big.paste(DARK, (x0 - 2 * S, y0 - 2 * S, x1 + 2 * S, y1 + 2 * S))
        big.paste(LIGHT, (x0, y0, x1, y1))
big.resize((N, N), Image.LANCZOS).save(OUT)
