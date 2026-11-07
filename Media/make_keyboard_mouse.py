"""A mouse, drawn big beside the Keyboard Map's mouse keys (KeyboardMap.lua),
each key with a line to its part: its outline, the line between its buttons,
its wheel and two side buttons. 128x256, white on clear (tinted in the game),
drawn bigger still and shrunk so its curves stay smooth. Coordinates are on a
64x128 grid (KeyboardMap.lua's MousePoint uses the same one), doubled here.
Our own, made from scratch here; usage, from the repo root:
python Media/make_keyboard_mouse.py"""
import os

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Textures", "KeyboardMouse.tga")
GRID = 2              # the picture's pixels per grid unit (64x128 grid)
W, H = 64 * GRID, 128 * GRID
SS = 8                # drawn this much bigger, then shrunk
K = GRID * SS         # grid unit -> drawing pixels

mask = Image.new("L", (W * SS, H * SS), 0)
d = ImageDraw.Draw(mask)


def box(x0, y0, x1, y1):
    return [x0 * K, y0 * K, x1 * K, y1 * K]


# The body: a tall rounded shape, the buttons' line across its upper third.
d.rounded_rectangle(box(8, 8, 56, 120), radius=24 * K, outline=255, width=round(2.5 * K))
d.line(box(9, 50, 55, 50), fill=255, width=round(1.5 * K))
d.line(box(32, 9, 32, 18), fill=255, width=round(1.5 * K))
d.line(box(32, 40, 32, 50), fill=255, width=round(1.5 * K))
# The wheel, over the middle of that line, with its ridges.
d.rounded_rectangle(box(27, 18, 37, 40), radius=5 * K, outline=255, width=round(1.5 * K))
for y in (24, 29, 34):
    d.line(box(29.5, y, 34.5, y), fill=255, width=round(1 * K))
# Two side buttons, on the left: button 5 (front, upper), button 4 (back, lower).
d.rounded_rectangle(box(2, 58, 9, 72), radius=3 * K, fill=255)
d.rounded_rectangle(box(2, 76, 9, 90), radius=3 * K, fill=255)

alpha = mask.resize((W, H), Image.LANCZOS)
image = Image.new("RGBA", (W, H), (255, 255, 255, 0))
image.putalpha(alpha)
image.save(OUT)
print("wrote", OUT)
