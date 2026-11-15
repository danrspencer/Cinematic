"""Textures/Link.tga: a 32x32 white chain link (two capsule outlines on a
diagonal), tinted in game. The Health & Resources page's link buttons
between its Keep up columns (PersonalResources.lua)."""
import math
import os
import struct

W = 32
A = ((7, 25), (13.5, 18.5))
B = ((18.5, 13.5), (25, 7))
RADIUS, THICK = 4.6, 2.6


def seg(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    t = max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


out = bytearray()
for y in range(W):
    for x in range(W):
        hits = 0
        for sx in range(4):
            for sy in range(4):
                px, py = x + (sx + .5) / 4, y + (sy + .5) / 4
                da = seg(px, py, *A[0], *A[1]) - RADIUS
                db = seg(px, py, *B[0], *B[1]) - RADIUS
                hits += abs(da) < THICK / 2 or abs(db) < THICK / 2
        out += bytes((255, 255, 255, int(255 * hits / 16)))

path = os.path.join(os.path.dirname(__file__), "..", "Textures", "Link.tga")
with open(path, "wb") as f:
    f.write(struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, W, W, 32, 0x28) + out)
