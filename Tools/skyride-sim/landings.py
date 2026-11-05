"""Flies every landing in sim.lua's LANDINGS through the real Skyriding Cam code
and checks how the camera comes back: how soon after touchdown it starts, how
long it takes, whether it stalls partway, and where it ends.
Usage (from the repo root): python Tools/skyride-sim/landings.py"""
import json, os, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
NAMES = ["cruise", "surge", "whirl", "glide", "dive", "turning", "halt", "touch", "touchlate", "again", "climbing", "ascent", "scroll", "scrolllate"]
START = 15  # yards: the distance the sim takes off at


def fly(name, tmp):
    path = os.path.join(tmp, name + ".json")
    subprocess.run([sys.executable, "-I", os.path.join(ROOT, "Tools", "offline", "run.py"),
                    os.path.join("Tools", "skyride-sim", "sim.lua"), "land:" + name, path],
                   cwd=ROOT, capture_output=True, text=True, timeout=300)
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def measure(run):
    rows = run["samples"]
    down = max(i for i in range(1, len(rows)) if rows[i - 1][6] == 1 and rows[i][6] == 0)
    t0 = rows[down][0]
    at0 = rows[down][1:4]
    after = rows[down:]
    end = rows[-1]
    moved = next((r[0] - t0 for r in after if abs(r[3] - at0[2]) > 0.1 or abs(r[1] - at0[0]) > 0.2 or abs(r[2] - at0[1]) > 0.2), None)
    settled = max((r[0] - t0 for r, q in zip(after[1:], after) if abs(r[3] - q[3]) > 0.001 or abs(r[1] - q[1]) > 0.002
                   or abs(r[2] - q[2]) > 0.002), default=0)
    dt = rows[1][0] - rows[0][0]
    speeds = [abs(r[3] - q[3]) / dt for r, q in zip(after[1:], after)]
    # A stall: the zoom stopping for over 0.25 s, then going on the same way.
    # (Out to its farthest, then in, is a turnaround, not a stall.)
    # (Nor the last half a yard creeping in: it can't be seen.)
    signed = [(r[3] - q[3]) / dt for r, q in zip(after[1:], after)]
    stall, gap, way = 0, 0, 0
    for i, v in enumerate(signed):
        if abs(v) <= 0.05:
            gap += 1
            continue
        now_way = 1 if v > 0 else -1
        if way == now_way and abs(after[i][3] - end[3]) > 0.5:
            stall = max(stall, gap * dt)
        way, gap = now_way, 0
    # The fastest it comes in once it's heading home (the zoom out before it, and
    # your own scroll, aside).
    home = [-v for v in signed if v < 0]
    # How far it came in for a landing it then took off from again.
    takeoffs = [i for i in range(1, len(rows)) if rows[i - 1][6] == 0 and rows[i][6] == 1]
    dip = None
    if len(takeoffs) > 1:
        first_down = max(i for i in range(1, takeoffs[-1]) if rows[i - 1][6] == 1 and rows[i][6] == 0)
        window = rows[first_down:takeoffs[-1] + 150]
        dip = rows[first_down][3] - min(r[3] for r in window)
    errors = [e["text"][:60] for e in run["events"] if e["kind"] == "error"]
    falsedive = [e["text"] for e in run["events"] if e["kind"] == "camera" and "diving (by speed" in e["text"]]
    return dict(dip=dip, cruise=rows[down - 5][3], at=at0, moved=moved, settled=settled, top=max(home or [0]), stall=stall, end=end[1:4], errors=errors,
                falsedive=falsedive)


def main():
    failed = 0
    print(f"{'landing':11} {'at touchdown':22} {'starts':>7} {'done':>6} {'top yd/s':>8} {'stall':>6}  ends at (zoom, turn, tilt)")
    with tempfile.TemporaryDirectory() as tmp:
        for name in NAMES:
            m = measure(fly(name, tmp))
            turn, tilt, zoom = m["at"]
            eturn, etilt, ezoom = m["end"]
            want = {"scroll": 10, "scrolllate": None}.get(name, START)
            bad = []
            # (Tilt: above where it started is the bug to catch; a little below, the
            # ground holds it there anyway.)
            if abs(eturn) > 1 or etilt < -1:
                bad.append("above where it started" if etilt < -1 else "not behind you")
            elif etilt > 5:
                bad.append("not back up")
            if want is not None and abs(ezoom - want) > 1.5:
                bad.append(f"zoom {ezoom:.1f}, wanted {want}")
            if m["stall"] > 0.3:
                bad.append("stalled")
            if name == "again" and abs(m["cruise"] - 20) > 1:
                bad.append(f"second flight at {m['cruise']:.1f} yd, not cruise")
            if m["top"] > 11 and name not in ("scroll", "scrolllate"):
                bad.append("comes in too fast")
            if m["errors"]:
                bad.append(str(m["errors"]))
            if name == "glide" and m["falsedive"]:
                bad.append("false dive")
            failed += 1 if bad else 0
            moved = "-" if m["moved"] is None else f"{m['moved']:.2f}s"
            print(f"{name:11} z{zoom:5.1f} t{tilt:6.1f} r{turn:6.1f}  {moved:>7} {m['settled']:5.1f}s {m['top']:8.1f} {m['stall']:5.2f}s"
                  f"  {ezoom:5.1f} {eturn:6.2f} {etilt:6.2f}  {'FAIL: ' + '; '.join(bad) if bad else 'ok'}"
                  + (f"  (came in {m['dip']:.1f} yd before taking off again)" if m["dip"] is not None else ""))
    print("all landings ok" if not failed else f"{failed} landing(s) failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
