"""How many more file-level locals each .lua can take before Lua 5.1's cap of
200 active locals in its main chunk (over it, the file doesn't compile and the
whole addon fails to load; luacheck doesn't see it). From the repo root:

    python -I Tools/local-room.py            files with under 10 to spare
    python -I Tools/local-room.py --all      every file, tightest first
    python -I Tools/local-room.py --min 20   files with under 20

Measured by adding locals at the end of a copy of each file until it no longer
compiles, so a do ... end block's locals (gone by the end) aren't counted.
Always exits 0 unless a file doesn't compile as it is (Tools/prerelease.py
shows the tight ones). Uses lupa (pip install lupa), else luac5.1.

The fix for a tight file: put a group of its locals in a table
(local Plate = {} ... Plate.x) or a do ... end block, as the file is touched.
"""
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CAP = 200


def compiler():
    try:
        import lupa.lua51 as lua51
        loadstring = lua51.LuaRuntime().eval("loadstring")

        def compiles(source):
            result = loadstring(source) # (a failure is nil, message: a tuple from lupa)
            if isinstance(result, tuple):
                result = result[0]
            return result is not None
        return compiles
    except ImportError:
        luac = shutil.which("luac5.1")
        if not luac:
            sys.exit("local-room: needs lupa (pip install lupa) or luac5.1")

        def compiles(source):
            return subprocess.run([luac, "-p", "-"], input=source.encode("utf-8"),
                                  capture_output=True).returncode == 0
        return compiles


def lua_files():
    out = subprocess.run(["git", "ls-files", "*.lua"], cwd=ROOT, capture_output=True, text=True).stdout.split()
    # (A file deleted but not committed yet is still listed: skipped.)
    return [f for f in out if not f.startswith(("Tools/", "Locales/", ".claude/"))
            and os.path.exists(os.path.join(ROOT, f))]


def room(compiles, source):
    if not compiles(source):
        return None
    low, high = 0, CAP
    while low < high:
        mid = (low + high + 1) // 2
        extra = "\n" + "\n".join("local cineRoom%d" % i for i in range(mid)) + "\n"
        if compiles(source + extra):
            low = mid
        else:
            high = mid - 1
    return low


def main():
    least = 10
    if "--min" in sys.argv:
        least = int(sys.argv[sys.argv.index("--min") + 1])
    show_all = "--all" in sys.argv
    compiles = compiler()
    rows, broken = [], []
    for path in lua_files():
        with open(os.path.join(ROOT, path), encoding="utf-8", errors="replace") as fh:
            spare = room(compiles, fh.read())
        if spare is None:
            broken.append(path)
        else:
            rows.append((spare, path))
    rows.sort()
    tight = [r for r in rows if show_all or r[0] < least]
    for spare, path in tight:
        print("%3d  %s" % (spare, path))
    for path in broken:
        print("  ?  %s (doesn't compile as it is)" % path)
    print("local room: %d files, %d with under %d locals to spare%s" % (
        len(rows), len([r for r in rows if r[0] < least]), least,
        ", tightest %s (%d)" % (rows[0][1], rows[0][0]) if rows else ""))
    return 1 if broken else 0


if __name__ == "__main__":
    sys.exit(main())
