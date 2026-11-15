"""How big the addon is, for watching it grow.

    python -I Tools/stats.py           # print the numbers
    python -I Tools/stats.py --save    # and add a line to Tools/stats.csv

Lines of code (locales apart), files, functions, the longest functions, the
files nearest Lua 5.1's 200-local cap (a rough count of the main chunk's
locals: lines starting with "local" at the left edge), one-time settings
updates in Core.lua, and the saved settings' size on this PC (the biggest
CinematicDB file under the game's WTF folders, if any).

The in-game numbers (login time, memory, ms per frame) come from the Profiler
page and /cine debug cpu: add them to the CSV by hand when measured.
"""
import csv
import datetime
import glob
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CSV = os.path.join(ROOT, "Tools", "stats.csv")
WOW = r"C:\Program Files (x86)\World of Warcraft"
LOCAL_CAP = 200

TOKEN = re.compile(
    r'--\[(=*)\[.*?\]\1\]|--[^\n]*|"(?:\\.|[^"\\\n])*"|\'(?:\\.|[^\'\\\n])*\'|\[(=*)\[.*?\]\2\]'
    r'|\b(function|end|do|then|repeat|until|if|for|while)\b', re.S)


def lua_files():
    out = subprocess.run(["git", "ls-files", "*.lua"], cwd=ROOT, capture_output=True, text=True).stdout
    return [f for f in out.split() if not f.startswith("Tools/")]


def functions(text):
    """(length in lines, first line, name) of every function, by keyword balance."""
    found, stack, loops = [], [], 0
    for m in TOKEN.finditer(text):
        word = m.group(3)
        if not word:
            continue
        line = text.count("\n", 0, m.start()) + 1
        if word == "function":
            start = text.rfind("\n", 0, m.start()) + 1
            name = (text[start:m.start()].strip() + " " + text[m.end():m.end() + 50].split("(")[0].strip()).strip()
            stack.append(("f", line, name[:60] or "(anon)"))
        elif word in ("for", "while"):
            loops += 1
        elif word == "do":
            if loops:
                loops -= 1
            stack.append(("b", line, ""))
        elif word in ("if", "repeat"):
            stack.append(("b", line, ""))
        elif word in ("end", "until") and stack:
            kind, first, name = stack.pop()
            if kind == "f":
                found.append((line - first, first, name))
    return found


def main_chunk_locals(text):
    n = 0
    for line in text.splitlines():
        m = re.match(r"local\s+(function\s+)?([\w\s,]+?)\s*(=|$|\()", line)
        if m:
            n += 1 if m.group(1) else len([x for x in m.group(2).split(",") if x.strip()])
    return n


def saved_settings_kb():
    best = 0
    for path in glob.glob(os.path.join(WOW, "*", "WTF", "Account", "*", "SavedVariables", "Cinematic*.lua")):
        best = max(best, os.path.getsize(path) // 1024)
    return best


def main():
    files = lua_files()
    code_lines = locale_lines = 0
    funcs, near_cap = [], []
    for f in files:
        with open(os.path.join(ROOT, f), encoding="utf-8", errors="replace") as h:
            text = h.read()
        n = text.count("\n")
        if f.startswith("Locales/"):
            locale_lines += n
            continue
        code_lines += n
        funcs += [(length, f, first, name) for length, first, name in functions(text)]
        count = main_chunk_locals(text)
        if count >= LOCAL_CAP - 30:
            near_cap.append((count, f))
    funcs.sort(reverse=True)
    near_cap.sort(reverse=True)
    with open(os.path.join(ROOT, "Core.lua"), encoding="utf-8", errors="replace") as h:
        migrations = len(set(re.findall(r"ns\.db\.(\w+V\d+) = true", h.read())))
    commits = subprocess.run(["git", "rev-list", "--count", "HEAD"], cwd=ROOT, capture_output=True,
                             text=True).stdout.strip()
    row = {
        "date": datetime.date.today().isoformat(),
        "commit": subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT, capture_output=True,
                                 text=True).stdout.strip(),
        "commits": commits,
        "lua_files": len(files),
        "code_lines": code_lines,
        "locale_lines": locale_lines,
        "functions": len(funcs),
        "funcs_over_300": sum(1 for x in funcs if x[0] > 300),
        "longest_func": funcs[0][0] if funcs else 0,
        "files_near_local_cap": len(near_cap),
        "migrations": migrations,
        "saved_kb": saved_settings_kb(),
    }
    for key, value in row.items():
        print("%-22s %s" % (key, value))
    print("\nlongest functions:")
    for length, f, first, name in funcs[:10]:
        print("  %5d  %s:%d  %s" % (length, f, first, name))
    print("\nfiles near the %d-local cap (rough count):" % LOCAL_CAP)
    for count, f in near_cap:
        print("  %4d  %s" % (count, f))
    if "--save" in sys.argv:
        new = not os.path.exists(CSV)
        with open(CSV, "a", newline="", encoding="utf-8") as h:
            writer = csv.DictWriter(h, fieldnames=list(row))
            if new:
                writer.writeheader()
            writer.writerow(row)
        print("\nadded to Tools/stats.csv")


if __name__ == "__main__":
    main()
