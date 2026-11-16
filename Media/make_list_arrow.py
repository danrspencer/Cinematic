"""The left list's fold arrow for Cinematic's own lines (Options.lua,
menu.PaintArrows): a gold triangle pointing right, drawn sharp at 32 px
(turned down in game while its line is open). Writes Textures/ListArrow.tga."""
import os
from PIL import Image, ImageDraw

S = 8
W = 32 * S
image = Image.new("RGBA", (W, W), (0, 0, 0, 0))
draw = ImageDraw.Draw(image)
# A dark edge, then the gold: light at the top, deeper at the bottom.
edge = [(9 * S, 5 * S), (26 * S, 16 * S), (9 * S, 27 * S)]
draw.polygon(edge, fill=(30, 18, 0, 230))
gold = Image.new("RGBA", (W, W))
gp = gold.load()
for y in range(W):
    t = y / W
    for x in range(W):
        gp[x, y] = (255, int(222 - 60 * t), int(70 - 60 * t), 255)
mask = Image.new("L", (W, W), 0)
ImageDraw.Draw(mask).polygon([(11 * S, 8 * S), (23 * S, 16 * S), (11 * S, 24 * S)], fill=255)
image.paste(gold, (0, 0), mask)
image = image.resize((32, 32), Image.LANCZOS)
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Textures", "ListArrow.tga")
image.save(out)
print("ok", os.path.normpath(out))
