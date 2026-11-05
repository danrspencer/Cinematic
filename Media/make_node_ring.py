"""Ring Cinematic draws on the minimap where ore, herbs or treasure show up
(Mark where it is: our mark, NodeSweep.lua): 64x64, white (tinted in game by
kind), its alpha a thin circle with soft edges both sides.
Our own, made from scratch here; usage: make_node_ring.py Textures/NodeRing.tga"""
import sys
from PIL import Image

N = 64
RADIUS = 27.0  # pixels of N to the middle of the line (room at the edge for the fade)
WIDTH = 5.0    # the line's full-strength width, pixels
SOFT = 2.0     # pixels each edge fades over
OUT = sys.argv[1] if len(sys.argv) > 1 else "NodeRing.tga"


def alpha(x, y):
    # Distance from the line's middle, at pixel centres.
    d = abs(((x + 0.5 - N / 2) ** 2 + (y + 0.5 - N / 2) ** 2) ** 0.5 - RADIUS) - WIDTH / 2
    # 1 within the line, fading to 0 over SOFT past it.
    t = min(1.0, max(0.0, 1 - d / SOFT))
    return round(255 * t * t * (3 - 2 * t))


image = Image.new("RGBA", (N, N))
image.putdata([(255, 255, 255, alpha(x, y)) for y in range(N) for x in range(N)])
image.save(OUT)
