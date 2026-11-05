"""Builds the Skyriding Cam flight sim page: runs sim.lua (the real
SkyrideCam.lua and CameraScripts.lua flying a made-up flight, offline) four
times: with the page's defaults (Follow your turns, pitch keys), with no
Blend, with Swing into the turn in place of the follow, and steering with the
mouse (no pitch keys), and puts them into sim_template.html.
Usage (from the repo root): python Tools/skyride-sim/build_sim.py <out .html>"""
import json, os, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
OUT = sys.argv[1]
EVERY = 2  # samples kept: every second one (0.04 s apart)

runs = {}
with tempfile.TemporaryDirectory() as tmp:
    for variant in ("page", "plain", "swing", "mouse"):
        path = os.path.join(tmp, variant + ".json")
        done = subprocess.run([sys.executable, "-I", os.path.join(ROOT, "Tools", "offline", "run.py"),
                               os.path.join("Tools", "skyride-sim", "sim.lua"), variant, path],
                              cwd=ROOT, capture_output=True, text=True, timeout=600)
        print(done.stdout.strip() or done.stderr.strip())
        if not os.path.exists(path):
            sys.exit("sim.lua wrote nothing for " + variant)
        with open(path, encoding="utf-8") as f:
            run = json.load(f)
        run["samples"] = [[round(v, 2) for v in row] for row in run["samples"][::EVERY]]
        errors = [e for e in run["events"] if e["kind"] == "error"]
        if errors:
            print("errors in", variant, errors[:3])
        runs[variant] = run

with open(os.path.join(HERE, "sim_template.html"), encoding="utf-8") as f:
    page = f.read()
page = page.replace("/*SIM_DATA*/null", json.dumps(runs, separators=(",", ":")))
with open(OUT, "w", encoding="utf-8", newline="\n") as f:
    f.write(page)
print("wrote", OUT, len(page) // 1024, "KB")
