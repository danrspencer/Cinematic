"""Lists translations the uncommitted changes need, per language.

    python -I .claude/skills/release/translations.py          keys new in the uncommitted changes
    python -I .claude/skills/release/translations.py --all    every code key missing anywhere

Only literal L["..."] keys are seen. Text translated another way (page names
via RegisterSubpage, tables run through ns.TranslateFields, keys built with ..)
has to be checked by reading the diff.

"New" keys: in an added line of `git diff HEAD` or an untracked .lua, and
missing from a locale. "Gone" keys: in a removed line and no longer anywhere in
the code (usually English that was reworded): their locale entries are stale and
should be moved onto the new wording.
"""
import os
import re
import subprocess
import sys

KEY = re.compile(r'\bL\["((?:[^"\\]|\\.)*)"\]')
ROOT = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True,
                      text=True, check=True).stdout.strip()
os.chdir(ROOT)


def git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True,
                          encoding="utf-8", errors="replace", check=True).stdout


def code_files():
    for d, dirs, files in os.walk("."):
        dirs[:] = [x for x in dirs if not x.startswith(".") and x not in ("Locales", "Tools", "docs")]
        for f in files:
            if f.endswith(".lua"):
                yield os.path.join(d, f)


def read(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        return fh.read()


def main():
    code = set()
    for f in code_files():
        code.update(KEY.findall(read(f)))
    locales = {}
    for f in sorted(os.listdir("Locales")):
        if f.endswith(".lua") and f != "Locales.lua":
            src = read(os.path.join("Locales", f))
            locales[f[:-4]] = set(re.findall(r'^\s*L\["((?:[^"\\]|\\.)*)"\]\s*=', src, re.M))

    if "--all" in sys.argv:
        wanted, gone = code, set()
    else:
        added, removed = set(), set()
        diff = git("diff", "HEAD", "--", "*.lua", ":!Locales", ":!Tools")
        for line in diff.splitlines():
            if line.startswith("+") and not line.startswith("+++"):
                added.update(KEY.findall(line))
            elif line.startswith("-") and not line.startswith("---"):
                removed.update(KEY.findall(line))
        for f in git("ls-files", "--others", "--exclude-standard", "--", "*.lua").splitlines():
            if not f.startswith(("Locales/", "Tools/")):
                added.update(KEY.findall(read(f)))
        wanted = added & code
        gone = removed - code

    total = 0
    for lang, keys in locales.items():
        missing = sorted(wanted - keys)
        stale = sorted(gone & keys)
        if not missing and not stale:
            continue
        print("== %s: %d missing, %d stale" % (lang, len(missing), len(stale)))
        for k in missing:
            print('  + L["%s"]' % k)
        for k in stale:
            print('  - L["%s"]' % k)
        total += len(missing) + len(stale)
    if not total:
        print("translations: nothing missing (%d new keys checked)" % len(wanted))


if __name__ == "__main__":
    main()
