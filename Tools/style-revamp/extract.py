"""Pulls what the mock-ups draw with out of the repo: the 16 style themes (their
real data, from StyleThemes.lua), the bar textures, the bar shapes, the target
marks, the preview scene and the bundled fonts. Writes mock/assets/*.json and
mock/assets/*.png. Run from anywhere."""
import base64, io, json, os, re, sys
from PIL import Image
import lupa

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "assets")
os.makedirs(OUT, exist_ok=True)

# --- themes: evaluate the THEMES table with Theme() as a pass-through
src = open(os.path.join(REPO, "StyleThemes.lua"), encoding="utf-8").read().split("\n")
start = next(i for i, l in enumerate(src) if l.startswith("local THEMES = {"))
end = next(i for i in range(start, len(src)) if src[i].startswith("}"))
chunk = "\n".join(src[start:end + 1]).replace("local THEMES", "THEMES")
lua = lupa.LuaRuntime(unpack_returned_tuples=True)
lua.execute("function Theme(info) return info end\n" + chunk)
def py(v):
    if lupa.lua_type(v) == "table":
        keys = list(v.keys())
        if keys and all(isinstance(k, int) for k in keys):
            return [py(v[k]) for k in sorted(keys)]
        return {str(k): py(v[k]) for k in keys}
    return v
themes = py(lua.globals().THEMES)
json.dump(themes, open(os.path.join(OUT, "themes.json"), "w"), indent=1)
print(len(themes), "themes")

def png_uri(im):
    buf = io.BytesIO(); im.save(buf, "PNG", optimize=True)
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()

assets = {}
for name in sorted(os.listdir(os.path.join(REPO, "Textures/Bars"))):
    im = Image.open(os.path.join(REPO, "Textures/Bars", name)).convert("RGBA")
    assets["bar_" + name[:-4].lower()] = png_uri(im)
for name in ["BarBevel", "BarCapsule", "BarChisel", "BarSoft"]:
    p = os.path.join(REPO, "Textures/Themes/Shapes", name + ".tga")
    if os.path.exists(p):
        im = Image.open(p).convert("RGBA")
        print(name, im.size)
        assets["shape_" + name[3:].lower()] = png_uri(im)
for name in ["TargetArrow", "TargetChevron", "TargetDiamond", "TargetGlow", "TargetBracket", "TargetCaret",
             "TargetCorner", "TargetUnderline", "SoftGlow"]:
    im = Image.open(os.path.join(REPO, "Textures", name + ".tga")).convert("RGBA")
    if max(im.size) > 128: im.thumbnail((128, 128))
    assets["tex_" + name.lower()] = png_uri(im)
for name in ["CodexCorner", "ForgeCorner", "GladeCorner", "ReelCorner", "RimeCorner"]:
    im = Image.open(os.path.join(REPO, "Textures/Themes", name + ".tga")).convert("RGBA")
    assets["corner_" + name[:-6].lower()] = png_uri(im)
scene = Image.open(os.path.join(REPO, "Textures/LetterboxScene.tga")).convert("RGB")
buf = io.BytesIO(); scene.save(buf, "JPEG", quality=82)
assets["scene"] = "data:image/jpeg;base64," + base64.b64encode(buf.getvalue()).decode()
fonts = {}
for f in os.listdir(os.path.join(REPO, "Fonts")):
    if f.endswith(".ttf") and f != "Blank.ttf":
        fonts[f[:-4]] = "data:font/ttf;base64," + base64.b64encode(open(os.path.join(REPO, "Fonts", f), "rb").read()).decode()
json.dump(assets, open(os.path.join(OUT, "images.json"), "w"))
json.dump(fonts, open(os.path.join(OUT, "fonts.json"), "w"))
print(len(assets), "images", sum(len(v) for v in assets.values()) // 1024, "KB;", len(fonts), "fonts",
      sum(len(v) for v in fonts.values()) // 1024, "KB")
