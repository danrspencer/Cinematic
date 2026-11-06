"""Rings Cinematic draws round action buttons' outlines with (ActionBarStyle.lua):
128x128, white (tinted in game), one per Thickness: ring N is N pixels thick on
a 45 pixel button, its outer edge at the texture's edge.
Our own, made from scratch here; usage: make_action_rings.py Textures"""
import os
import sys
from PIL import Image

N = 128
BUTTON = 45.0  # the game's main bar button, pixels
SOFT = 1.5     # pixels each edge fades over
OUT = sys.argv[1] if len(sys.argv) > 1 else "."


def alpha(x, y, width):
    outer = N / 2 - SOFT
    d = ((x + 0.5 - N / 2) ** 2 + (y + 0.5 - N / 2) ** 2) ** 0.5
    # Distance outside the line (negative: within it), fading to 0 over SOFT.
    past = max(d - outer, outer - width - d)
    t = min(1.0, max(0.0, 1 - past / SOFT))
    return round(255 * t * t * (3 - 2 * t))


for size in range(1, 11):
    width = size * N / BUTTON
    image = Image.new("RGBA", (N, N))
    image.putdata([(255, 255, 255, alpha(x, y, width)) for y in range(N) for x in range(N)])
    image.save(os.path.join(OUT, "ActionRing%d.tga" % size))
