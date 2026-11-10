"""Art for Square action buttons on retail (ActionBarStyle.lua), whose own square
has cut corners: ActionBevelMask.tga, the shape filled (the icon's mask), and
ActionBevelRing1 to 10.tga, the line round it, N pixels thick. 128x128, white
on clear (tinted in game), the shape's outer edge at the texture's edge.
Our own, made from scratch here; usage: make_action_bevel.py Textures"""
import os
import sys
from PIL import Image

N = 128
SQUARE = 41.0  # retail's square on its 45 pixel button (2 in each side)
CUT = 4.0      # how far each corner is cut back along both edges, pixels
SOFT = 1.5     # pixels each edge fades over
OUT = sys.argv[1] if len(sys.argv) > 1 else "."
SCALE = N / SQUARE


def outside(x, y):
    """How far (texture pixels) a point is outside the shape; negative: inside."""
    h = N / 2 - SOFT
    ax, ay = abs(x + 0.5 - N / 2), abs(y + 0.5 - N / 2)
    corner = (ax + ay - (2 * h - CUT * SCALE)) / 2 ** 0.5
    return max(ax - h, ay - h, corner)


def smooth(t):
    t = min(1.0, max(0.0, t))
    return round(255 * t * t * (3 - 2 * t))


def save(name, alpha):
    image = Image.new("RGBA", (N, N))
    image.putdata([(255, 255, 255, alpha(x, y)) for y in range(N) for x in range(N)])
    image.save(os.path.join(OUT, name), compression=None)


save("ActionBevelMask.tga", lambda x, y: smooth(1 - outside(x, y) / SOFT))
for size in range(1, 11):
    width = size * SCALE
    save("ActionBevelRing%d.tga" % size,
         lambda x, y, width=width: smooth(1 - max(outside(x, y), -width - outside(x, y)) / SOFT))
