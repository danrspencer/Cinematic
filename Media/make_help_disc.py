"""Disc behind Cinematic's "?" help icons: 32x32, white, its alpha a circle
with a soft edge. The game's round portrait mask (TempPortraitAlphaMask) is
large and shrinks to the icon's 18 px with no smoothing, so its edge looks
jagged; this one is near that size and fades over 2 pixels.
Our own, made from scratch here; usage: make_help_disc.py Textures/HelpDisc.tga"""
import sys
from PIL import Image

N = 32
RADIUS = 15.0  # pixels of N (a pixel clear at the edge, for the fade)
SOFT = 2.0     # pixels the edge fades over
OUT = sys.argv[1] if len(sys.argv) > 1 else "HelpDisc.tga"


def alpha(x, y):
    # Distance outside the circle (negative inside), at pixel centres.
    d = ((x + 0.5 - N / 2) ** 2 + (y + 0.5 - N / 2) ** 2) ** 0.5 - RADIUS
    # Fades from 1 at SOFT inside the edge to 0 at the edge.
    t = min(1.0, max(0.0, -d / SOFT))
    return round(255 * t * t * (3 - 2 * t))


image = Image.new("RGBA", (N, N))
image.putdata([(255, 255, 255, alpha(x, y)) for y in range(N) for x in range(N)])
image.save(OUT)
