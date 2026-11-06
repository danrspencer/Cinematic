"""Builds Tools/style-lab/out/shots.html: every /cine debug themeshots run from
the game's Screenshots folders, by client, run, theme and scene, for judging
the themes on real art. From the repo root:

    python Tools/style-lab/build_shots.py

A run is shots a few seconds apart. Its themes come from their order (a full
run is always the same 18), or from the log in SavedVariables for a run of one
theme. What's worked out is kept in out/shots_index.json, as the log trims.
Out of git: the shots are from the game and show character names.
"""
import json
import os
import re
import sys
from datetime import datetime

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
SHOTS = os.path.join(OUT, "shots")
INDEX = os.path.join(OUT, "shots_index.json")
GAME = r"C:\Program Files (x86)\World of Warcraft"
CLIENTS = {"_retail_": "Retail", "_forever_": "Forever", "_classic_era_": "ClassicEra"}
START = datetime(2026, 11, 5, 22, 0)  # (the first run: older shots aren't these)
THEMES = [("game", "The game's"), ("reel", "Silver Screen"), ("codex", "Gilded Codex"), ("forge", "Emberforge"),
          ("glade", "Moonlit Glade"), ("rime", "Frostbound"),
          ("vanguard", "Crimson Vanguard"), ("hearth", "Hearthside"), ("cathedral", "Cathedral"), ("rune", "Runestone"),
          ("fel", "Fel Pact"), ("void", "Void Whisper")]
SCENES = ["HUD", "Visions", "Real frames"]
MAX_GAP = 4  # (seconds between two shots of one run)
WIDTH = 1720


def when(name):
    m = re.match(r"WoWScrnShot_(\d\d)(\d\d)(\d\d)_(\d\d)(\d\d)(\d\d)\.jpg$", name)
    if not m:
        return None
    mo, d, y, h, mi, s = (int(x) for x in m.groups())
    return datetime(2000 + y, mo, d, h, mi, s)


def runs_of(folder):
    shots = sorted((t, f) for t, f in ((when(f), f) for f in os.listdir(folder)) if t and t >= START)
    runs, run = [], []
    for t, f in shots:
        if run and (t - run[-1][0]).total_seconds() > MAX_GAP:
            runs.append(run)
            run = []
        run.append((t, f))
    if run:
        runs.append(run)
    return [r for r in runs if len(r) % 3 == 0]


def logged_theme(log, run):
    """The theme a run of one theme logged, as it took its last shot."""
    first, last = run[0][0].strftime("%H:%M:%S"), run[-1][0].strftime("%H:%M:%S")
    for stamp, theme in re.findall(r'"(\d\d:\d\d:\d\d)[.\d]* plates: plate health style: .*?theme (\w+);', log):
        if first <= stamp <= last:
            return theme
    return None


def main():
    os.makedirs(SHOTS, exist_ok=True)
    index = json.load(open(INDEX, encoding="utf-8")) if os.path.exists(INDEX) else {}
    runs = []
    names = dict(THEMES)
    for folder, client in CLIENTS.items():
        shots = os.path.join(GAME, folder, "Screenshots")
        # (Whichever account folder has the addon's saved settings.)
        accounts = os.path.join(GAME, folder, "WTF", "Account")
        logs = [os.path.join(accounts, a, "SavedVariables", "CinematicDev.lua")
                for a in (os.listdir(accounts) if os.path.isdir(accounts) else [])]
        saved = next((path for path in logs if os.path.exists(path)), "")
        log = open(saved, encoding="utf-8", errors="replace").read() if saved else ""
        if not os.path.isdir(shots):
            continue
        for run in runs_of(shots):
            key = client + ":" + run[0][1]
            # (More than one theme: always in the list's order, a run cut short too.)
            if len(run) > 3:
                themes = [k for k, _ in THEMES][:len(run) // 3]
            elif index.get(key, ["unknown"])[0] != "unknown":
                themes = index[key]
            else:
                themes = [logged_theme(log, run) or "unknown"] * (len(run) // 3)
            index[key] = themes
            items = []
            for i, (_, name) in enumerate(run):
                local = client.lower() + "-" + name
                path = os.path.join(SHOTS, local)
                if not os.path.exists(path):
                    im = Image.open(os.path.join(shots, name)).convert("RGB")
                    if im.width > WIDTH:
                        im = im.resize((WIDTH, round(im.height * WIDTH / im.width)), Image.LANCZOS)
                    im.save(path, quality=80, optimize=True)
                theme = themes[i // 3]
                items.append({"file": "shots/" + local, "theme": theme, "themeName": names.get(theme, theme),
                              "scene": SCENES[i % 3]})
            runs.append({"id": key, "client": client, "at": run[0][0].strftime("%Y-%m-%d %H:%M"),
                         "label": "%s, %s" % (client, run[0][0].strftime("%b %-d %H:%M" if os.name != "nt" else "%b %#d %H:%M")),
                         "full": len(run) == 18, "items": items})
    json.dump(index, open(INDEX, "w", encoding="utf-8"), indent=0)
    runs.sort(key=lambda r: r["at"], reverse=True)
    notes = json.load(open(os.path.join(HERE, "shot_notes.json"), encoding="utf-8"))
    data = {"runs": runs, "themes": [{"key": k, "name": n} for k, n in THEMES], "scenes": SCENES, "notes": notes}
    template = open(os.path.join(HERE, "shots_template.html"), encoding="utf-8").read()
    blob = json.dumps(data, ensure_ascii=False, separators=(",", ":")).replace("</", "<\\/")
    open(os.path.join(OUT, "shots.html"), "w", encoding="utf-8").write(template.replace("/*DATA*/null", blob))
    size = sum(os.path.getsize(os.path.join(SHOTS, f)) for f in os.listdir(SHOTS)) / 1e6
    print("%d runs, %d shots, %.1f MB" % (len(runs), sum(len(r["items"]) for r in runs), size))
    for r in runs:
        print("  %s: %d shots, %s" % (r["label"], len(r["items"]),
                                      "all themes" if r["full"] else ",".join(sorted({i["theme"] for i in r["items"]}))))


if __name__ == "__main__":
    sys.exit(main())
