"""Builds Tools/style-lab/out/style-lab.html: every frame the Style pages can
preview, drawn by the addon's own code (dump.lua) in each style theme, on a
page you can look through and compare. From the repo root:

    python Tools/style-lab/build.py [retail|forever]

The addon's own textures go in as they are. The game's art isn't ours to copy
(nor to reach from here), so anything of the game's is a stand-in drawn by
standin() below: the same shape and rough color, never the picture. Text uses
web fonts near the game's for the same reason.
"""
import base64
import hashlib
import io
import json
import math
import os
import re
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(HERE, "out")


def png(im):
    buf = io.BytesIO()
    im.save(buf, "PNG", optimize=True)
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()


def ours(path):
    """An Interface\\AddOns\\<addon>\\... texture of ours, or None."""
    m = re.match(r"(?i)interface\\addons\\[^\\]+\\(.+)$", path)
    if not m:
        return None
    rel = m.group(1).replace("\\", "/")
    for ext in ("", ".tga", ".blp", ".png"):
        full = os.path.join(ROOT, rel + ext)
        if os.path.isfile(full) and not full.endswith(".blp"):
            im = Image.open(full).convert("RGBA")
            if max(im.size) > 512:
                im.thumbnail((512, 512))
            return im
    return None


def vertical(top, bottom, w=64, h=32):
    y = np.linspace(0, 1, h)[:, None, None]
    a = np.array(top, dtype=float)
    b = np.array(bottom, dtype=float)
    rgba = (a * (1 - y) + b * y) * np.ones((h, w, 1))
    return Image.fromarray(rgba.astype(np.uint8), "RGBA")


def disc(size=128):
    im = Image.new("RGBA", (size * 2, size * 2), (0, 0, 0, 0))
    ImageDraw.Draw(im).ellipse((2, 2, size * 2 - 3, size * 2 - 3), fill=(255, 255, 255, 255))
    return im.resize((size, size), Image.LANCZOS)


def icon(name):
    """A stand-in spell icon: a painted square in a color from its name."""
    h = hashlib.md5(name.lower().encode()).digest()
    hue = h[0] / 255
    size = 64
    yy, xx = np.mgrid[0:size, 0:size] / (size - 1)
    r = np.sqrt((xx - 0.42) ** 2 + (yy - 0.38) ** 2)
    base = np.array([0.5 + 0.5 * math.cos(6.28 * (hue + k / 3)) for k in range(3)])
    base = 0.34 + 0.42 * base  # (quiet: a stand-in shouldn't shout over the theme)
    glow = np.clip(1.15 - r * 1.5, 0, 1)[..., None]
    rgb = base * (0.22 + 0.78 * glow) + glow ** 3 * 0.35
    edge = np.minimum.reduce([xx, yy, 1 - xx, 1 - yy])[..., None]
    rgb = rgb * np.clip(edge * 14, 0.35, 1)
    out = np.dstack([np.clip(rgb, 0, 1) * 255, np.full((size, size), 255.0)])
    return Image.fromarray(out.astype(np.uint8), "RGBA")


def bar(kind="soft"):
    if kind == "game":
        return vertical((235, 235, 235, 255), (150, 150, 150, 255), 64, 16)
    return vertical((255, 255, 255, 255), (190, 190, 190, 255), 64, 16)


def panel(color=(20, 20, 26, 235)):
    return Image.new("RGBA", (8, 8), color)


def spark():
    u = np.linspace(-1, 1, 16)[None, :]
    v = np.linspace(-1, 1, 32)[:, None]
    a = np.exp(-(u / 0.3) ** 2) * (1 - v ** 4) * 255
    out = np.dstack([np.full(a.shape, 255.0)] * 3 + [a])
    return Image.fromarray(out.astype(np.uint8), "RGBA")


def edge_strip():
    """A stand-in tooltip border (the page draws it as a line)."""
    return Image.new("RGBA", (8, 8), (160, 160, 170, 255))


def standin(name):
    low = name.lower()
    if "white8x8" in low:
        return Image.new("RGBA", (8, 8), (255, 255, 255, 255))
    if "portraitalphamask" in low or "circle" in low or "mask" in low:
        return disc()
    if "\\icons\\" in low or low.startswith("inv_") or low.startswith("spell_") or low.startswith("ability_"):
        return icon(name)
    if "spark" in low:
        return spark()
    if "background" in low or "-bg" in low or "dialogbox" in low:
        return panel()
    if any(k in low for k in ("statusbar", "-bar", "bar-", "fill", "barfill", "skills")):
        return bar("game")
    if "border" in low:
        return edge_strip()
    if "emptyslot" in low or "iconframe-slot" in low:
        return panel((30, 30, 34, 200))
    if "quickslot" in low or "iconframe" in low:
        return None  # (a button's ring: left out, the icon shows square)
    return None


def main():
    client = sys.argv[1] if len(sys.argv) > 1 else "retail"
    os.makedirs(OUT, exist_ok=True)
    dump = os.path.join(OUT, "dump.json")
    run = subprocess.run([sys.executable, "-I", "Tools/offline/run.py", "Tools/style-lab/dump.lua", client,
                          dump.replace("\\", "/")], cwd=ROOT, capture_output=True, text=True, encoding="utf-8",
                         stdin=subprocess.DEVNULL)
    print(run.stdout.strip())
    if run.returncode != 0:
        sys.exit(run.stderr or "dump.lua failed")
    data = json.load(open(dump, encoding="utf-8"))

    assets, missing = {}, {}
    for shots in data["shots"].values():
        for shot in shots.values():
            if not shot:
                continue
            for item in shot["items"]:
                for key in ("file", "atlas", "mask", "bg", "edge"):
                    name = item.get(key)
                    if not name or name in assets or name in missing:
                        continue
                    im = ours(name) or standin(name)
                    if im is None:
                        missing[name] = True
                    else:
                        assets[name] = png(im)
    data["assets"] = assets
    data["missing"] = sorted(missing)
    print("%d assets, %d left out: %s" % (len(assets), len(missing), ", ".join(sorted(missing))[:300]))

    template = open(os.path.join(HERE, "lab_template.html"), encoding="utf-8").read()
    blob = json.dumps(data, ensure_ascii=False, separators=(",", ":")).replace("</", "<\\/")
    html = template.replace("/*DATA*/null", blob)
    path = os.path.join(OUT, "style-lab.html")
    open(path, "w", encoding="utf-8").write(html)
    print("%s, %.1f MB" % (path, len(html) / 1e6))


if __name__ == "__main__":
    main()
