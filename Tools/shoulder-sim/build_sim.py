"""Builds the Shoulder Cam sim page: runs sim.lua (the real ShoulderCam.lua on a
made-up session, offline) for each session and puts them into sim_template.html.
Also runs the "sweep" session, which only checks the test commands (no page).
Exits with an error if a check fails that isn't one of KNOWN below.
Usage (from the repo root): python Tools/shoulder-sim/build_sim.py <out .html>"""
import json, os, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
OUT = sys.argv[1]
EVERY = 5  # samples kept: every fifth one (0.1 s apart)
SESSIONS = ("page", "chained", "hud", "mounted", "tall", "relog", "fight", "decline")
# Checks expected to fail until Phase 1 of Tools/shoulder-test-plan.md fixes them.
KNOWN = {("fight", "Cast bar back on its place"),
         ("fight", "PRD back on its place")}

runs, failed = {}, []
with tempfile.TemporaryDirectory() as tmp:
    for session in SESSIONS + ("sweep",):
        path = os.path.join(tmp, session + ".json")
        done = subprocess.run([sys.executable, "-I", os.path.join(ROOT, "Tools", "offline", "run.py"),
                               os.path.join("Tools", "shoulder-sim", "sim.lua"), session, path],
                              cwd=ROOT, capture_output=True, text=True, timeout=600)
        print("\n".join(line for line in done.stdout.splitlines() if "/cine log" not in line) or done.stderr.strip())
        if not os.path.exists(path):
            sys.exit("sim.lua wrote nothing for " + session)
        with open(path, encoding="utf-8") as f:
            run = json.load(f)
        failed += [(session, c["name"]) for c in run["checks"] if not c["ok"] and (session, c["name"]) not in KNOWN]
        if session != "sweep":
            run["samples"] = [[round(v, 3) for v in row] for row in run["samples"][::EVERY]]
            runs[session] = run

with open(os.path.join(HERE, "sim_template.html"), encoding="utf-8") as f:
    page = f.read()
page = page.replace("/*SIM_DATA*/null", json.dumps(runs, separators=(",", ":")))
with open(OUT, "w", encoding="utf-8", newline="\n") as f:
    f.write(page)
print("wrote", OUT, len(page) // 1024, "KB")
if failed:
    sys.exit("new failed checks: " + str(failed))
