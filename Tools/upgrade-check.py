"""The upgrade check: what this release changes for players who already have
the addon. From the repo root:

    python -I Tools/upgrade-check.py                 last tag -> working tree
    python -I Tools/upgrade-check.py v2.1.10         that version -> working tree
    python -I Tools/upgrade-check.py A B             commit A -> commit B

Players keep their saved settings across updates. Defaults are written into
them at the first load, so a changed default never reaches an existing
player, while a once-only update (Migrations.lua) or a new setting does. On
each client this loads the old version's code (git archive) on the stand-in
game (Tools/offline/upgrade-dump.lua) and then the new one on what it saved:
- as a player who installed the old version and changed nothing;
- as one who then turned every on/off setting the other way (their own
  choices: an update must keep them);
- as you, on your own saved settings (Cinematic.lua, each client), if found;
and lists, per client:
  CHANGED   a saved value the update rewrites (a once-only update): players
            see something other than what they had (their own choice too);
  NEW ON    a new setting that's on for existing players (a new feature
            they'll see without asking for it);
  NEW       other new settings, and what existing players start with when
            it isn't what a new install gets;
  DROPPED   a saved value the new code removes or no longer has a default
            for (a renamed setting with no update loses the player's choice);
  DEFAULT   a default that changed: new installs get it, existing players
            keep the old one (often meant; say so in the review);
  TYPE      a default whose kind changed (true -> "text"): old saved values
            of the old kind are still there for the new code to read;
  RELOAD    a value the new code changes again at every load (a load step
            that isn't once-only): players' choice keeps going back;
  FALLBACK  a code default in the diff (db.x or 12 -> or 16, ~= false ->
            == true): players who never set it see the new one.
Each line is something to look at, not an error. Exit 1 only when a version
doesn't load or an update errors. Needs lupa (pip install lupa).
"""
import glob
import io
import os
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WOW = os.environ.get("CINE_WOW", r"C:\Program Files (x86)\World of Warcraft")
CLIENTS = {"forever": "_forever_", "retail": "_retail_"}
TOC = "Cinematic.toc"  # (the player copy: what players run)
DUMP = "Tools/offline/upgrade-dump.lua"
FLAG = re.compile(r'^db\["[^"]*V\d+"\]$')
# Saved values that change by themselves (clocks, logs, counters): not the update's doing.
NOISE = re.compile(r'^db\["(log|errors?|errorLog|sweepLog|prereleaseLog|prerelease|profilerDigest|'
                   r'lastLogin|lastSeen|lastVersion|seenVersion|version|recap\w*|stats\w*|session\w*)"\]')
LINE = re.compile(r'^((?:db|default)\[.*?\]) = (.*)$')


def git(*args, cwd=ROOT):
    return subprocess.run(["git"] + list(args), cwd=cwd, capture_output=True, text=True,
                          encoding="utf-8", errors="replace")


def export(ref, into):
    """The ref's files in a folder of their own, with today's dump script."""
    data = subprocess.run(["git", "archive", "--format=tar", ref], cwd=ROOT, capture_output=True).stdout
    if not data:
        sys.exit("upgrade check: can't read %s from git" % ref)
    with tarfile.open(fileobj=io.BytesIO(data)) as tar:
        tar.extractall(into)
    os.makedirs(os.path.join(into, "Tools", "offline"), exist_ok=True)
    shutil.copy(os.path.join(ROOT, DUMP), os.path.join(into, DUMP))


def run(code, client, saved, out, saved_out=None, drop=(), flip=False):
    cmd = [sys.executable, "-I", os.path.join(ROOT, "Tools", "offline", "run.py"), DUMP, client, TOC, saved, out]
    if saved_out:
        cmd.append(saved_out)
    env = dict(os.environ, CINE_DROP_FLAGS=",".join(drop), CINE_FLIP="1" if flip else "")
    result = subprocess.run(cmd, cwd=code, capture_output=True, text=True, encoding="utf-8",
                            errors="replace", stdin=subprocess.DEVNULL, env=env)
    errors = [l for l in result.stdout.splitlines() if l.startswith("update failed")]
    if result.returncode != 0 or not os.path.exists(out):
        errors.append((result.stdout + result.stderr).strip().splitlines()[-1:] or ["didn't load"])
        errors = [e if isinstance(e, str) else e[0] for e in errors]
    return errors


def settled(code, client, saved, out, saved_out, drop=(), flip=False):
    """Loaded, saved, and loaded again: some load steps take two loads to
    settle (a setting worked out from others), which isn't the update's doing."""
    first = out + ".first"
    errors = run(code, client, saved, first + ".txt", first + ".lua", drop, flip)
    return errors or run(code, client, first + ".lua", out, saved_out)


def read(path):
    db, defaults = {}, {}
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            m = LINE.match(line.rstrip("\n"))
            if m:
                (db if m.group(1).startswith("db") else defaults)[m.group(1)] = m.group(2)
    return db, defaults


def kind(value):
    if value in ("true", "false"):
        return "boolean"
    if value.startswith('"'):
        return "text"
    if value == "{}":
        return "list"
    return "number" if re.match(r"^-?[\d.]", value) else value


def top(path):
    return path.split("]")[0] + "]"


def reloads(before, after):
    """Values a second load of the same code changes again: lines, keys."""
    out, keys = [], set()
    for key in sorted(set(before) | set(after)):
        if before.get(key) != after.get(key) and not NOISE.match(key):
            out.append("RELOAD  %s: %s -> %s at the next load" % (key[2:], before.get(key), after.get(key)))
            keys.add(key)
    return out, keys


def compare(before, after, fresh_new, unstable=()):
    """Lines for one player: their settings before and after the update."""
    out = []
    flags = quiet = 0
    for key in sorted(set(before) | set(after)):
        if FLAG.match(key):
            flags += key not in before
            continue
        if NOISE.match(key) or key in unstable:
            continue
        was, now = before.get(key), after.get(key)
        if was == now:
            continue
        name = key[2:]
        if was is None:
            fresh = fresh_new.get(key)
            if now == "true" and not name.startswith('["tabOn:'):  # (a tab's switch: shows nothing new)
                out.append("NEW ON  %s = true%s" % (name, "" if fresh in (None, now) else
                                                    "   (new installs get %s)" % fresh))
            elif fresh not in (None, now):
                out.append("NEW     %s = %s   (new installs get %s)" % (name, now, fresh))
            else:
                quiet += 1
        elif now is None:
            out.append("DROPPED %s (was %s)" % (name, was))
        else:
            out.append("CHANGED %s: %s -> %s" % (name, was, now))
    if quiet:
        out.append("(and %d new settings that start off or as for new installs)" % quiet)
    return out, flags


def compare_defaults(old, new, saved_before, saved_after):
    out = []
    for key in sorted(set(old) & set(new)):
        if old[key] == new[key] or saved_after.get("db" + key[7:]) == new[key]:
            continue  # (an update brings existing players the new one too: CHANGED above)
        name = key[7:]
        if kind(old[key]) != kind(new[key]) and "{}" not in (old[key], new[key]):
            out.append("TYPE    %s: %s -> %s (saved %s values are still there)" %
                       (name, old[key], new[key], kind(old[key])))
        else:
            out.append("DEFAULT %s: %s -> %s (existing players keep %s)" % (name, old[key], new[key], old[key]))
    for key in sorted(set(old) - set(new)):
        if ("db" + key[7:]) in saved_before and top(key) == key:
            out.append("DROPPED %s: no default any more (players' saved %s stays, unread?)" %
                       (key[7:], saved_before["db" + key[7:]]))
    return out


FALLBACK = re.compile(r'\b(?:db|DB|saved|settings|s|d)\.(\w+)\s*(or\s*([-\w."\']+)|~=\s*false|==\s*true)')


def fallbacks(old_ref, new_ref):
    """Code defaults (x or 12, ~= false) that changed in the diff, by setting."""
    args = ["diff", "-U0", old_ref] + ([new_ref] if new_ref else []) + ["--", "*.lua", ":!Dev/*", ":!Tools/*",
                                                                        ":!Locales/*"]
    removed, added = {}, {}
    for line in git(*args).stdout.splitlines():
        if not line[:1] in "+-" or line.startswith(("+++", "---")):
            continue
        for m in FALLBACK.finditer(line):
            where = removed if line[0] == "-" else added
            where.setdefault(m.group(1), set()).add(re.sub(r"\s+", " ", m.group(2)))
    out = []
    for key in sorted(set(removed) & set(added)):
        gone, came = removed[key] - added[key], added[key] - removed[key]
        if gone and came:
            out.append("FALLBACK %s: %s -> %s" % (key, " / ".join(sorted(gone)), " / ".join(sorted(came))))
    return out


def main():
    refs = [a for a in sys.argv[1:] if not a.startswith("-")]
    old_ref = refs[0] if refs else git("describe", "--tags", "--abbrev=0").stdout.strip()
    new_ref = refs[1] if len(refs) > 1 else None
    scratch = tempfile.mkdtemp(prefix="cine-upgrade-")
    failed = []
    findings = 0
    try:
        old_code = os.path.join(scratch, "old")
        export(old_ref, old_code)
        new_code = ROOT
        if new_ref:
            new_code = os.path.join(scratch, "new")
            export(new_ref, new_code)
        print("upgrade check: %s -> %s, %s" % (old_ref, new_ref or "working tree", TOC))
        defaults_done = False
        for client, folder in CLIENTS.items():
            f = lambda name: os.path.join(scratch, "%s-%s" % (client, name))
            # A player who installed the old version and changed nothing.
            errors = settled(old_code, client, "fresh", f("old.txt"), f("old.lua"))
            errors += run(new_code, client, f("old.lua"), f("upgraded.txt"), f("upgraded.lua"))
            errors += run(new_code, client, f("upgraded.lua"), f("reloaded.txt"))
            errors += run(new_code, client, "fresh", f("new.txt"))
            if errors:
                failed += ["%s: %s" % (client, e) for e in errors]
                continue
            before, old_defaults = read(f("old.txt"))
            after, _ = read(f("upgraded.txt"))
            fresh, new_defaults = read(f("new.txt"))
            old_flags = {k[6:-2] for k in before if FLAG.match(k)}
            unstable, keys = reloads(after, read(f("reloaded.txt"))[0])
            lines, flags = compare(before, after, fresh, keys)
            lines += unstable
            print("\n%s, a player on %s with no changes of their own (%d new once-only updates ran):" %
                  (client, old_ref, flags))
            print("".join("  %s\n" % l for l in lines) or "  nothing changes\n", end="")
            findings += len(lines)
            if not defaults_done:
                lines = compare_defaults(old_defaults, new_defaults, before, after)
                print("\ndefaults (%s):" % client)
                print("".join("  %s\n" % l for l in lines) or "  none changed\n", end="")
                findings += len(lines)
                defaults_done = True
            # A player who turned every on/off setting the other way.
            errors = settled(old_code, client, f("old.lua"), f("flip-old.txt"), f("flip-old.lua"), flip=True)
            errors += run(new_code, client, f("flip-old.lua"), f("flip-new.txt"), f("flip-new.lua"))
            errors += run(new_code, client, f("flip-new.lua"), f("flip-again.txt"))
            if errors:
                failed += ["%s, every setting changed: %s" % (client, e) for e in errors]
            else:
                flipped = read(f("flip-new.txt"))[0]
                unstable, keys = reloads(flipped, read(f("flip-again.txt"))[0])
                lines, _ = compare(read(f("flip-old.txt"))[0], flipped, fresh, keys)
                lines = [l for l in lines if l.startswith(("CHANGED", "DROPPED", "NEW ON"))] + unstable
                print("\n%s, a player on %s who turned every on/off setting the other way:" % (client, old_ref))
                print("".join("  %s\n" % l for l in lines) or "  nothing of theirs changes\n", end="")
                findings += len(lines)
            # You, with your own settings: the old and the new version each
            # load them as they are, but for the done-flags this release adds
            # (taken off, so its updates run as they will for players).
            new_flags = {k[6:-2] for k in fresh if FLAG.match(k)}
            for path in sorted(glob.glob(os.path.join(WOW, folder, "WTF", "Account", "*", "SavedVariables",
                                                      "Cinematic.lua"))):
                drop = sorted(new_flags - old_flags)
                errors = settled(old_code, client, path, f("mine-old.txt"), f("mine-old.lua"), drop)
                errors += run(new_code, client, path, f("mine-new.txt"), f("mine-new.lua"), drop)
                errors += run(new_code, client, f("mine-new.lua"), f("mine-again.txt"))
                if errors:
                    failed += ["%s, your settings: %s" % (client, e) for e in errors]
                    continue
                mine = read(f("mine-new.txt"))[0]
                unstable, keys = reloads(mine, read(f("mine-again.txt"))[0])
                lines, _ = compare(read(f("mine-old.txt"))[0], mine, fresh, keys)
                lines = [l for l in lines if l.startswith(("CHANGED", "DROPPED"))] + unstable
                print("\n%s, your own settings (%s):" % (client, path.split("Account")[1].split("SavedVariables")[0]
                                                         .strip("\\/")))
                print("".join("  %s\n" % l for l in lines) or "  nothing of yours changes\n", end="")
                findings += len(lines)
        lines = fallbacks(old_ref, new_ref)
        print("\ncode defaults in the diff:")
        print("".join("  %s\n" % l for l in lines) or "  none changed\n", end="")
        findings += len(lines)
    finally:
        shutil.rmtree(scratch, ignore_errors=True)
    for e in failed:
        print("FAIL " + e)
    print("\nupgrade check: %s" % ("%d FAILED" % len(failed) if failed else
                                     "%d things change for existing players" % findings))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
