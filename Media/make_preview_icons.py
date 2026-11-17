"""The Style preview's small icon buttons (StylePages.lua, PreviewIcon): one
sheet of white line icons, tinted in game. 4 x 2 cells of 32 px, in order:
pop out, put back, dock, close, fold, unfold, scene, undock.
Writes Textures/PreviewIcons.tga (128 x 64)."""
import os
from PIL import Image, ImageDraw

S = 8  # drawn 8x, then shrunk: smooth lines
C = 32 * S
image = Image.new("RGBA", (4 * C, 2 * C), (0, 0, 0, 0))
draw = ImageDraw.Draw(image)
W = int(2.6 * S)  # line width
WHITE = (255, 255, 255, 255)


def P(cell, x, y):
    col, row = cell % 4, cell // 4
    return (col * C + x * S, row * C + y * S)


def line(cell, points):
    pts = [P(cell, x, y) for x, y in points]
    draw.line(pts, fill=WHITE, width=W, joint="curve")
    r = W / 2
    for px, py in pts:
        draw.ellipse((px - r, py - r, px + r, py + r), fill=WHITE)


def box(cell, x0, y0, x1, y1):
    line(cell, [(x0, y0), (x1, y0), (x1, y1), (x0, y1), (x0, y0)])


# 0 pop out: a box open at its top right, an arrow leaving it.
line(0, [(14, 8), (8, 8), (8, 24), (24, 24), (24, 18)])
line(0, [(15, 17), (25, 7)])
line(0, [(18, 7), (25, 7), (25, 14)])
# 1 put back: an arrow curling back down into a tray.
line(1, [(23, 8), (23, 14), (11, 14)])
line(1, [(15, 10), (11, 14), (15, 18)])
line(1, [(7, 20), (7, 25), (25, 25), (25, 20)])
# 2 dock: a window with its side panel.
box(2, 6, 8, 26, 24)
line(2, [(19, 8), (19, 24)])
# 3 close: an X.
line(3, [(9, 9), (23, 23)])
line(3, [(23, 9), (9, 23)])
# 4 fold: a chevron up.
line(4, [(8, 20), (16, 12), (24, 20)])
# 5 unfold: a chevron down.
line(5, [(8, 12), (16, 20), (24, 12)])
# 6 scene: hills under a sun.
line(6, [(5, 24), (12, 15), (17, 20), (21, 16), (27, 24), (5, 24)])
cx, cy, r = P(6, 22, 9)[0], P(6, 22, 9)[1], 3 * S
draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=WHITE)
# 7 undock: a window with an arrow out of its side.
box(7, 5, 9, 20, 23)
line(7, [(14, 16), (27, 16)])
line(7, [(23, 12), (27, 16), (23, 20)])

image = image.resize((128, 64), Image.LANCZOS)
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Textures", "PreviewIcons.tga")
image.save(out)
print("ok", os.path.normpath(out))
