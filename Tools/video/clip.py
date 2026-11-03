"""The showcase video's recording tracker.

clips.json holds every clip to record and how far each is; playbook.md is
made from it (don't edit that by hand). A take is the newest recording in
the captures folder, moved to the library and named after its clip:
"V06 quest-cam t1.mp4".

    python Tools/video/clip.py               where we are, and the next clips
    python Tools/video/clip.py done V06      newest recording = V06's take
    python Tools/video/clip.py done V06 --note "good light"
    python Tools/video/clip.py done V06 --file "<path>"   that recording instead
    python Tools/video/clip.py skip V06      won't record it (--note why)
    python Tools/video/clip.py redo V06      back to do (its takes are kept)
    python Tools/video/clip.py pending       recordings not given to a clip yet
    python Tools/video/clip.py render        remake playbook.md
    python Tools/video/clip.py scan V06 [take]   contact sheets of a take (newest if
                                             no take): a frame at each picture change
                                             and every few seconds, its time on it
    python Tools/video/clip.py mark V06 2 "0:04 the camera swings in" "0:12 ..."
                                             the take's marks (replaces any it had)
"""
import json
import re
import subprocess
import os
import shutil
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "clips.json")
PLAYBOOK = os.path.join(HERE, "playbook.md")
VIDEO = (".mp4", ".mkv", ".mov")
MARK = {"todo": "[ ]", "done": "[x]", "skip": "[-]"}


def load():
    with open(DATA, encoding="utf-8") as f:
        return json.load(f)


def save(data):
    with open(DATA, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    render(data)


def find(data, clip_id):
    for clip in data["clips"]:
        if clip["id"].lower() == clip_id.lower():
            return clip
    sys.exit(f"No clip {clip_id}.")


def pending(data):
    """Recordings in the captures folder, newest first (any there is unclaimed:
    a take is moved out)."""
    folder = data["captures"]
    if not os.path.isdir(folder):
        return []
    files = [os.path.join(folder, n) for n in os.listdir(folder) if n.lower().endswith(VIDEO)]
    return sorted(files, key=os.path.getmtime, reverse=True)


def done(data, clip, path, note):
    if not path:
        files = pending(data)
        if not files:
            sys.exit(f"Nothing in {data['captures']} to give to {clip['id']}.")
        path = files[0]
        if len(files) > 1:
            print(f"(newest of {len(files)} recordings; the others stay: `pending` lists them)")
    if not os.path.isfile(path):
        sys.exit(f"No file {path}.")
    if time.time() - os.path.getmtime(path) < 3:
        sys.exit("That recording is still being written: stop recording first.")
    os.makedirs(data["library"], exist_ok=True)
    take = len(clip["takes"]) + 1
    ext = os.path.splitext(path)[1].lower()
    name = f"{clip['id']} {clip['slug']} t{take}{ext}"
    target = os.path.join(data["library"], name)
    shutil.move(path, target)
    clip["takes"].append({"file": name, "from": os.path.basename(path), "note": note or ""})
    clip["status"] = "done"
    print(f"{os.path.basename(path)}  ->  {target}")


SCENE = 0.02   # picture change worth a frame (ffmpeg's scene score)
EVERY = 3      # and a frame every this many seconds anyway
SHEET = 16     # frames per contact sheet (4 x 4)


def stamp(seconds):
    return f"{int(seconds // 60)}:{seconds % 60:04.1f}"


def take_of(data, clip, number):
    if not clip["takes"]:
        sys.exit(f"{clip['id']} has no takes.")
    if number is None:
        return clip["takes"][-1]
    if not 1 <= number <= len(clip["takes"]):
        sys.exit(f"{clip['id']} has takes 1 to {len(clip['takes'])}.")
    return clip["takes"][number - 1]


def scan(data, clip, number):
    from PIL import Image, ImageDraw, ImageFont
    take = take_of(data, clip, number)
    path = os.path.join(data["library"], take["file"])
    duration = float(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of",
                                     "csv=p=0", path], capture_output=True, text=True).stdout.strip())
    found = subprocess.run(["ffmpeg", "-hide_banner", "-i", path, "-vf",
                            f"scale=480:-1,select='gt(scene,{SCENE})',showinfo", "-an", "-f", "null", "-"],
                           capture_output=True, text=True, encoding="utf-8", errors="replace").stderr
    changes = [float(t) for t in re.findall(r"pts_time:([0-9.]+)", found)]
    times = sorted(set([round(t, 1) for t in changes] + [float(t) for t in range(0, int(duration), EVERY)]))
    kept = []
    for t in times:  # (two within half a second: the picture change wins)
        if kept and t - kept[-1] < 0.5:
            if t in changes:
                kept[-1] = t
            continue
        kept.append(t)
    out = os.path.join(data["library"], ".scan", os.path.splitext(take["file"])[0])
    os.makedirs(out, exist_ok=True)
    for old in os.listdir(out):
        os.remove(os.path.join(out, old))
    font = ImageFont.truetype("arial.ttf", 22)
    frames = []
    for t in kept:
        png = os.path.join(out, f"f{t:08.2f}.png")
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", str(t), "-i", path, "-frames:v", "1", "-vf",
                        "scale=480:-1", png], check=True)
        if os.path.exists(png):
            frames.append((t, png))
    sheets = []
    for n in range(0, len(frames), SHEET):
        group = frames[n:n + SHEET]
        with Image.open(group[0][1]) as first:
            w, h = first.size
        cols = 4
        sheet = Image.new("RGB", (w * cols, h * ((len(group) + cols - 1) // cols)), "black")
        draw = ImageDraw.Draw(sheet)
        for i, (t, png) in enumerate(group):
            x, y = (i % cols) * w, (i // cols) * h
            with Image.open(png) as frame:
                sheet.paste(frame, (x, y))
            label = stamp(t) + (" *" if any(abs(t - c) < 0.05 for c in changes) else "")
            draw.rectangle([x, y, x + 110, y + 28], fill="black")
            draw.text((x + 6, y + 2), label, fill="yellow", font=font)
        name = os.path.join(out, f"sheet{len(sheets) + 1:02d}.png")
        sheet.save(name)
        sheets.append(name)
    for _, png in frames:
        os.remove(png)
    print(f"{take['file']}: {stamp(duration)} long, {len(changes)} picture changes, {len(frames)} frames "
          f"(* = a change)")
    for name in sheets:
        print("  " + name)


def counts(data):
    clips = data["clips"]
    n = {s: sum(1 for c in clips if c["status"] == s) for s in MARK}
    return n, len(clips)


def summary(data):
    n, total = counts(data)
    print(f"Done {n['done']}/{total}, skipped {n['skip']}, to record {n['todo']}.")
    names = {s["id"]: s["name"] for s in data["sessions"]}
    todo = [c for c in data["clips"] if c["status"] == "todo"]
    for clip in todo[:3]:
        hub = f"  [hub: {clip['hub']}]" if clip.get("hub") else ""
        print(f"  next: {clip['id']} {clip['title']} ({names[clip['session']]}, {clip['client']}){hub}")
    left = pending(data)
    if left:
        print(f"{len(left)} recording(s) waiting in {data['captures']}.")


def zoom(clip):
    z = clip.get("zoom", "wide")
    return z + (f": {clip['zoomOn']}" if clip.get("zoomOn") else "")


def cell(text):
    return (text or "").replace("|", "/").replace("\n", " ")


def render(data):
    n, total = counts(data)
    out = [
        "# Showcase video: recording playbook",
        "",
        "Made from `clips.json` by `clip.py`: don't edit by hand.",
        "",
        f"**Done {n['done']} / {total}**, skipped {n['skip']}, to record {n['todo']}.  ",
        f"OBS records to `{data["captures"]}` → takes go to `{data['library']}` as `V06 quest-cam t1.mp4`.",
        "",
        "One clip at a time: set up, record in OBS, stop, then say which clip it was.",
        "**Hub** = a Demo Hub button (`/cine demo <key>`, or Dev > Demo Commands). "
        "★ = for the short video. NEW = added in the last days.",
        "",
        "Before each session: Clean slate (hub), a showcase profile, Captions on for carousels and off for B-roll.",
        "",
        "**Zoom** (how the clip is framed in the edit):",
        "",
    ] + [f"- **{k}**: {v}" for k, v in data.get("zoomGuide", {}).items()] + [""]
    if data.get("script"):
        out += ["## Script", "", "| Time | Section | Shot | On screen |", "|---|---|---|---|"]
        out += ["| " + " | ".join(cell(p.strip()) for p in line.split("|")) + " |" for line in data["script"]]
        out.append("")
    for session in data["sessions"]:
        clips = [c for c in data["clips"] if c["session"] == session["id"]]
        done_here = sum(1 for c in clips if c["status"] == "done")
        out += [f"## {session['id']}. {session['name']} ({done_here}/{len(clips)})", "", session["where"], "",
                "| | Clip | What | Zoom | Client | Hub | How | Takes |", "|---|---|---|---|---|---|---|---|"]
        for c in clips:
            tags = (" ★" if c.get("short") else "") + (" NEW" if c.get("new") else "")
            takes = "<br>".join(cell(t["file"] + (f" ({t['note']})" if t.get("note") else "")
                                     + (": " + " · ".join(t["marks"]) if t.get("marks") else ""))
                                for t in c["takes"])
            if c["status"] == "skip" and c.get("skipNote"):
                takes = cell("skipped: " + c["skipNote"])
            how = cell(c.get("do", ""))
            if c.get("steps"):
                how += "<br>" + "<br>".join(f"{i}. {cell(step)}" for i, step in enumerate(c["steps"], 1))
            out.append(f"| {MARK[c['status']]} | {c['id']} | {cell(c['title'])}{tags} | {zoom(c)} | {c['client']} | "
                       f"{cell(c.get('hub', ''))} | {how} | {takes} |")
        out.append("")
    with open(PLAYBOOK, "w", encoding="utf-8") as f:
        f.write("\n".join(out))


def main(args):
    sys.stdout.reconfigure(encoding="utf-8")
    data = load()
    note = file = None
    if "--note" in args:
        i = args.index("--note")
        note = args[i + 1]
        del args[i:i + 2]
    if "--file" in args:
        i = args.index("--file")
        file = args[i + 1]
        del args[i:i + 2]
    cmd = args[0] if args else "status"
    if cmd == "status":
        summary(data)
    elif cmd == "pending":
        for path in pending(data):
            print(f"  {time.strftime('%H:%M', time.localtime(os.path.getmtime(path)))}  {os.path.basename(path)}")
    elif cmd == "scan" and len(args) > 1:
        scan(data, find(data, args[1]), int(args[2]) if len(args) > 2 else None)
    elif cmd == "mark" and len(args) > 3:
        take = take_of(data, find(data, args[1]), int(args[2]))
        take["marks"] = args[3:]
        save(data)
        print(f"{take['file']}: {len(args) - 3} marks")
    elif cmd == "render":
        render(data)
    elif cmd in ("done", "skip", "redo") and len(args) > 1:
        clip = find(data, args[1])
        if cmd == "done":
            done(data, clip, file, note)
        elif cmd == "skip":
            clip["status"], clip["skipNote"] = "skip", note or ""
        else:
            clip["status"] = "todo"
        save(data)
        summary(data)
    else:
        print(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
