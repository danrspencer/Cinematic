"""Builds ScreenEffectsData.lua: every full-screen effect in the game's data
(the FullScreenEffect, TextureBlendSet and ScreenEffect tables), read from
wago.tools' CSV export of the client's own DB2 files. Only numbers from the
game's data: file numbers, colours, scroll rates, the names Blizzard gave them.

Run: python -I Tools/offline/screen_effects.py   (writes ScreenEffectsData.lua)
For /cine debug screenfx (ScreenEffectScout.lua, dev copy only).
"""
import csv
import io
import os
import sys
import urllib.request

BASE = "https://wago.tools/db2/%s/csv"
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "ScreenEffectsData.lua")


def table(name):
    req = urllib.request.Request(BASE % name, headers={"User-Agent": "Cinematic-addon-dev"})
    with urllib.request.urlopen(req) as r:
        text = r.read().decode("utf-8-sig")
    rows = list(csv.DictReader(io.StringIO(text)))
    return {row["ID"]: row for row in rows}, rows


def num(value):
    f = float(value or 0)
    if f == int(f):
        return str(int(f))
    return ("%.4f" % f).rstrip("0").rstrip(".")


def lua_string(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main():
    full, full_rows = table("FullScreenEffect")
    blends, _ = table("TextureBlendSet")
    _, screen_rows = table("ScreenEffect")
    version = ""
    names = {}
    for row in screen_rows:
        fid = row["FullScreenEffectID"]
        if fid != "0":
            names.setdefault(fid, []).append(row["Name"].strip())
    out = [
        "-- Made by Tools/offline/screen_effects.py from the game's own data tables",
        "-- (FullScreenEffect, TextureBlendSet, ScreenEffect): don't edit by hand.",
        "-- Each: id, name (the screen effects that use it, as Blizzard named them),",
        "-- overlay file, layers { file, scaleU, scaleV, scrollU, scrollV, mode },",
        "-- multiply { r, g, b, strength }, add { r, g, b, strength },",
        "-- mask { offsetY, size, power }, saturation, blur, fade in/out ms, flags.",
        "-- Layer 1 is the edge mask (the shape); 2 and 3 move inside it.",
        "local _, ns = ...",
        "ns.SCREEN_EFFECTS = {",
    ]
    count = 0
    for row in sorted(full_rows, key=lambda r: int(r["ID"])):
        fid = row["ID"]
        blend = blends.get(row["TextureBlendSetID"])
        layers = []
        if blend:
            for i in range(3):
                f = blend["TextureFileDataID_%d" % i]
                if f and f != "0":
                    layers.append("{ %s, %s, %s, %s, %s, %s }" % (
                        f, num(blend["TextureScaleU_%d" % i]), num(blend["TextureScaleV_%d" % i]),
                        num(blend["TextureScrollRateU_%d" % i]), num(blend["TextureScrollRateV_%d" % i]),
                        num(blend["ModX_%d" % i])))
        overlay = row["OverlayTextureFileDataID"] or "0"
        if not layers and overlay == "0":
            continue
        name = " / ".join(dict.fromkeys(names.get(fid, [])))[:160] or "(no screen effect names it)"
        out.append(
            "\t{ id = %s, name = %s, overlay = %s, layers = { %s },\n"
            "\t\tmultiply = { %s, %s, %s, %s }, add = { %s, %s, %s, %s },\n"
            "\t\tmask = { %s, %s, %s }, saturation = %s, blur = %s, fade = { %s, %s }, flags = %s },"
            % (fid, lua_string(name), overlay, ", ".join(layers),
               num(row["ColorMultiplyRed"]), num(row["ColorMultiplyGreen"]), num(row["ColorMultiplyBlue"]),
               num(row["ColorMultiplyMultiplier"]),
               num(row["ColorAdditionRed"]), num(row["ColorAdditionGreen"]), num(row["ColorAdditionBlue"]),
               num(row["ColorAdditionMultiplier"]),
               num(row["MaskOffsetY"]), num(row["MaskSizeMultiplier"]), num(row["MaskPower"]),
               num(row["Saturation"]), num(row["BlurIntensity"]),
               row["EffectFadeInMs"], row["EffectFadeOutMs"], row["Flags"]))
        count += 1
    out.append("}")
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(out) + "\n")
    print("%d effects -> %s" % (count, os.path.normpath(OUT)))


if __name__ == "__main__":
    sys.exit(main())
