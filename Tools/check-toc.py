"""The dev TOC is the release TOC plus dev-only files, in the same order.

    python -I Tools/check-toc.py

Checks, exit 1 on any problem:
- every file the release TOC loads, the dev TOC loads too, in the same order
  (so players run the load order the dev copy is tested with);
- both TOCs list the same Interface and SavedVariables lines;
- every file only the dev TOC loads is left out of the package (.pkgmeta's
  ignore), so a test file never ships by mistake;
- every file either TOC names exists.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def read_toc(name):
    files, meta = [], {}
    with open(os.path.join(ROOT, name), encoding="utf-8-sig") as f:
        for line in f:
            line = line.strip()
            m = re.match(r"## (Interface|SavedVariables|SavedVariablesPerCharacter): *(.*)", line)
            if m:
                meta[m.group(1)] = m.group(2).strip()
            elif line and not line.startswith("#"):
                files.append(line.replace("\\", "/"))
    return files, meta


def pkgmeta_ignores():
    ignores = []
    with open(os.path.join(ROOT, ".pkgmeta"), encoding="utf-8") as f:
        for line in f:
            m = re.match(r"\s*-\s*(\S+)", line)
            if m:
                ignores.append(m.group(1).rstrip("/"))
    return ignores


def ignored(path, ignores):
    return any(path == i or path.startswith(i + "/") for i in ignores)


def main():
    problems = []
    release, release_meta = read_toc("Cinematic.toc")
    dev, dev_meta = read_toc("CinematicDev.toc")
    for key in ("Interface", "SavedVariables", "SavedVariablesPerCharacter"):
        if release_meta.get(key) != dev_meta.get(key):
            problems.append("## %s differs: %r vs %r" % (key, release_meta.get(key), dev_meta.get(key)))
    missing = [f for f in release if f not in dev]
    for f in missing:
        problems.append("%s: in Cinematic.toc, not in CinematicDev.toc" % f)
    shared = [f for f in dev if f in release]
    expected = [f for f in release if f in dev]
    if shared != expected:
        for i, (a, b) in enumerate(zip(expected, shared)):
            if a != b:
                problems.append("load order differs from file %d: Cinematic.toc has %s where CinematicDev.toc has %s"
                                % (i + 1, a, b))
                break
    ignores = pkgmeta_ignores()
    # (ChangelogCommits.dev.lua is made by Tools/commits.sh and not kept in git:
    # the package never has it.)
    for f in dev:
        if f not in release and not ignored(f, ignores) and f != "ChangelogCommits.dev.lua":
            problems.append("%s: dev copy only, but not in .pkgmeta's ignore (it would ship)" % f)
    for f in set(release + dev):
        if f != "ChangelogCommits.dev.lua" and not os.path.exists(os.path.join(ROOT, f)):
            problems.append("%s: named in a TOC, no such file" % f)
    for p in problems:
        print("toc: " + p)
    print("toc: %d problems (%d release files, %d dev-only)" % (len(problems), len(release), len(dev) - len(shared)))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
