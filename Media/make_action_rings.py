"""Rings Cinematic draws round action buttons' outlines with (ActionBarStyle.lua):
128x128, white (tinted in game), one per Thickness: ring N is N pixels thick on
a 45 pixel button, its outer edge at the texture's edge. ActionRoundMask.tga: the
round button's icon mask, ending a little inside the rings' outer edge (the
game's round mask, bigger and softer, left the icon's pale edge showing past them).
Our own, made from scratch here; usage: make_action_rings.py Textures"""
import math
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


# The icon's mask: whole to IN inside the rings' outer edge, gone by there.
IN = 1.5  # texture pixels


def mask(x, y):
    edge = N / 2 - SOFT - IN
    d = ((x + 0.5 - N / 2) ** 2 + (y + 0.5 - N / 2) ** 2) ** 0.5
    t = min(1.0, max(0.0, (edge - d) / SOFT))
    return round(255 * t * t * (3 - 2 * t))


image = Image.new("RGBA", (N, N))
image.putdata([(255, 255, 255, mask(x, y)) for y in range(N) for x in range(N)])
image.save(os.path.join(OUT, "ActionRoundMask.tga"))


# ActionRoundGlow.tga: the glow round a round button's inside edge while you cast
# (the game's, square, shows past a circle): brightest at the mask's edge, fading
# in over GLOW pixels (on the 45 pixel button).
GLOW = 7.0


def glow(x, y):
    edge = N / 2 - SOFT - IN
    d = ((x + 0.5 - N / 2) ** 2 + (y + 0.5 - N / 2) ** 2) ** 0.5
    if d > edge:
        t = max(0.0, 1 - (d - edge) / SOFT)
    else:
        t = max(0.0, 1 - (edge - d) / (GLOW * N / BUTTON))
        t = t * t
    return round(255 * t)


image = Image.new("RGBA", (N, N))
image.putdata([(255, 255, 255, glow(x, y)) for y in range(N) for x in range(N)])
image.save(os.path.join(OUT, "ActionRoundGlow.tga"))


# ActionRoundProc.tga: a proc's glow on a round button, laid SPREAD pixels past the
# button's round edge all round (ActionBarStyle.lua places it so): brightest on the
# edge, fading in over PROC_IN pixels and out over SPREAD, so a proc reads at a glance.
EDGE_R = 20.5  # the round edge's radius on the button, pixels (retail's, 2 in)
SPREAD = 9.0
PROC_IN = 10.0


CORE = 1.6  # pixels each side of the edge at full strength: the band (the game's is bright and tight)


def proc(x, y):
    scale = (N / 2) / (EDGE_R + SPREAD)
    d = ((x + 0.5 - N / 2) ** 2 + (y + 0.5 - N / 2) ** 2) ** 0.5 / scale
    off = abs(d - EDGE_R)
    if off <= CORE:
        return 255
    t = max(0.0, 1 - (off - CORE) / ((SPREAD if d > EDGE_R else PROC_IN) - CORE))
    return round(255 * t ** 2.2)


image = Image.new("RGBA", (N, N))
image.putdata([(255, 255, 255, proc(x, y)) for y in range(N) for x in range(N)])
image.save(os.path.join(OUT, "ActionRoundProc.tga"))


# ActionRoundSparks.tga: the sparks that run round a proc's band (turned in game):
# SPARKS bright heads on the edge, each with a tail fading back TAIL degrees.
SPARKS = 3
TAIL = 70.0


def sparks(x, y):
    scale = (N / 2) / (EDGE_R + SPREAD)
    dx, dy = x + 0.5 - N / 2, y + 0.5 - N / 2
    d = (dx * dx + dy * dy) ** 0.5 / scale
    radial = max(0.0, 1 - abs(d - EDGE_R) / 2.2)
    if radial <= 0:
        return 0
    angle = math.degrees(math.atan2(dy, dx)) % 360
    best = 0.0
    for k in range(SPARKS):
        behind = (360.0 / SPARKS * k - angle) % 360
        if behind <= TAIL:
            best = max(best, (1 - behind / TAIL) ** 2)
    return round(255 * best * radial ** 1.5)


image = Image.new("RGBA", (N, N))
image.putdata([(255, 255, 255, sparks(x, y)) for y in range(N) for x in range(N)])
image.save(os.path.join(OUT, "ActionRoundSparks.tga"))
