"""Which release a fix is in, for the "fixed in vX.Y.Z" line of a player reply.

usage (from the repo root):
  python -I .claude/skills/support/fixed_in.py <commit>... [--player vX.Y.Z]
  python -I .claude/skills/support/fixed_in.py --since vX.Y.Z [paths...] [--grep word]

  <commit>   the fix's commit(s): prints the first release tag that contains
             each (git tag --contains, so a fix-only release cut off an older
             tag counts right), or "next update (vX.Y.Z+1)" when none does yet,
             and the client gates (retail / Forever / Classic Era) in its diff
  --player   the player's version: says whether they already have the fix
             (then it isn't the same bug)
  --since    the player's version: every commit after it (touching paths, or
             whose message has --grep word), each with the release it's in,
             to see whether their problem was already fixed
"""
import re
import subprocess
import sys

GATES = re.compile(r"ns\.isRetail|ns\.isForever|ns\.isClassicEra|ns\.CLIENT|WOW_PROJECT_ID|isRetail|isForever")


def git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True, encoding="utf-8",
                          errors="replace").stdout


def ver(tag):
    m = re.match(r"^v?(\d+(?:\.\d+)*)$", tag.strip())
    return tuple(int(x) for x in m.group(1).split(".")) if m else None


def tags():
    found = [t for t in git("tag").split() if ver(t)]
    return sorted(found, key=ver)


def next_version():
    latest = tags()[-1]
    parts = list(ver(latest))
    parts[-1] += 1
    return latest, "v" + ".".join(str(p) for p in parts)


def first_tag(commit):
    have = [t for t in git("tag", "--contains", commit).split() if ver(t)]
    return min(have, key=ver) if have else None


PUSHED = None


def pushed(tag):
    """Whether the tag is on GitHub (a pushed tag is what uploads the release to CurseForge)."""
    global PUSHED
    if PUSHED is None:
        out = git("ls-remote", "--tags", "origin")
        PUSHED = {line.split("refs/tags/")[-1].replace("^{}", "") for line in out.splitlines()} if out else False
    return None if PUSHED is False else tag in PUSHED


def released_in(commit):
    tag = first_tag(commit)
    if tag:
        state = pushed(tag)
        note = "" if state else (" (tag NOT on origin yet: not out to players)" if state is False else
                                 " (couldn't reach origin to check it's out)")
        return tag, "fixed in %s%s" % (tag, note)
    latest, upcoming = next_version()
    return None, "not released yet: next update (%s, a forecast: latest tag is %s)" % (upcoming, latest)


def gates(commit):
    lines = []
    for line in git("show", "--format=", "-U0", commit).splitlines():
        if line.startswith("+++ "):
            current = line[6:]
        elif line[:1] in "+-" and not line.startswith(("+++", "---")) and GATES.search(line):
            lines.append("    %s: %s" % (current, line[:140].strip()))
    return lines


def main():
    args = sys.argv[1:]
    player = since = word = None
    rest = []
    i = 0
    while i < len(args):
        if args[i] in ("--player", "--since", "--grep"):
            value = args[i + 1]
            if args[i] == "--player":
                player = value
            elif args[i] == "--since":
                since = value
            else:
                word = value
            i += 2
        else:
            rest.append(args[i])
            i += 1
    if not rest and not since:
        sys.exit(__doc__)
    latest, upcoming = next_version()
    print("latest release: %s (next would be %s)" % (latest, upcoming))

    if since:
        tag = since if since.startswith("v") else "v" + since
        cmd = ["log", "--format=%h%x09%ad%x09%s", "--date=short", "%s..HEAD" % tag]
        if word:
            cmd += ["-i", "--grep", word]
        if rest:
            cmd += ["--", *rest]
        lines = git(*cmd).splitlines()
        print("%d commits since %s%s%s:" % (len(lines), tag, (" touching " + " ".join(rest)) if rest else "",
                                            (" mentioning " + word) if word else ""))
        for line in lines:
            commit, date, subject = (line.split("\t") + ["", ""])[:3]
            t = first_tag(commit) or "unreleased"
            print("  %s %s [%s] %s" % (commit, date, t, subject[:160]))
        return

    for commit in rest:
        subject = git("log", "-1", "--format=%h %ad %s", "--date=short", commit).strip()
        if not subject:
            print("%s: no such commit" % commit)
            continue
        tag, text = released_in(commit)
        print("\n%s\n  %s" % (subject[:200], text))
        if player:
            p, t = ver(player), ver(tag) if tag else None
            if p is None:
                print("  player version %r not understood" % player)
            elif t and p >= t:
                print("  player's %s ALREADY HAS this fix: their problem is something else" % player)
            else:
                print("  player's %s doesn't have it: updating to %s fixes it" % (player, tag or upcoming))
        found = gates(commit)
        if found:
            print("  client gates in the diff (check the fix reaches the player's client):")
            print("\n".join(found[:15]))
        else:
            print("  no client gates in the diff (all clients)")


if __name__ == "__main__":
    main()
