"""Exact /cine find ids for some words, per client, from the settings as the
offline harness builds them (Tools/offline/ids.lua: the same list as /cine
debug ids, the player copy's Cinematic.toc).

usage (from the repo root):
  python -I .claude/skills/support/find_ids.py <words...> [--client forever|retail|both]
      [--version vX.Y.Z] [--hidden] [--top N]

  words      what to look for: label words, or part of an id (camelCase works)
  --client   which client's settings (default both)
  --version  also check each id is in that release (the player's version)
  --hidden   also list matching settings with no control (only /run reaches them)
  --top      how many matches to show (default 12)
"""
import os
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile

ROOT = os.getcwd()
CLIENTS = ("forever", "retail")


def run_ids(root, client, own_tools):
    """Lines of ids.lua for one client, run in root (a checkout or an extracted tag)."""
    env = dict(os.environ)
    tools = os.path.join(root, "Tools", "offline")
    if own_tools:
        # (An older tag has no ids.lua: today's, run on that tag's files.)
        for name in ("ids.lua", "run.py"):
            shutil.copy(os.path.join(ROOT, "Tools", "offline", name), os.path.join(tools, name))
    result = subprocess.run([sys.executable, "-I", "Tools/offline/run.py", "Tools/offline/ids.lua", client,
                             "Cinematic.toc"], cwd=root, env=env, stdin=subprocess.DEVNULL,
                            capture_output=True, text=True, encoding="utf-8", errors="replace")
    ids, hidden = {}, {}
    for line in result.stdout.splitlines():
        parts = line.split("\t")
        if parts[0] == "id" and len(parts) >= 4:
            ids[parts[1]] = (parts[2], parts[3])
        elif parts[0] == "hidden" and len(parts) >= 4:
            hidden[parts[1]] = (parts[2], parts[3])
    if not ids:
        sys.stderr.write("ids.lua gave nothing for %s in %s:\n%s\n" % (client, root, result.stderr[-1500:]))
    return ids, hidden


def tag_tree(tag):
    """The tag's files, extracted into a temp folder (never a checkout of the repo)."""
    folder = tempfile.mkdtemp(prefix="cine-tag-")
    archive = os.path.join(folder, "tag.tar")
    with open(archive, "wb") as out:
        subprocess.run(["git", "archive", tag], cwd=ROOT, stdout=out, check=True)
    with tarfile.open(archive) as tar:
        tar.extractall(os.path.join(folder, "tree"))
    return folder, os.path.join(folder, "tree")


def words_of(text):
    text = re.sub(r"([a-z])([A-Z])", r"\1 \2", text)
    return [w for w in re.split(r"[^a-z0-9]+", text.lower()) if w]


def score(query, id_, page, label):
    hay = " ".join(words_of(id_) + words_of(page) + words_of(label))
    label_words = " ".join(words_of(label))
    total = 0
    for word in query:
        if re.search(r"\b" + re.escape(word), label_words):
            total += 3
        elif re.search(r"\b" + re.escape(word), hay):
            total += 2
        elif word in hay or word in id_.lower():
            total += 1
        else:
            return 0  # (every word must be somewhere)
    if " ".join(query) in label_words:
        total += 2
    return total


def main():
    args = sys.argv[1:]
    client, version, hidden_too, top = "both", None, False, 12
    words = []
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--client":
            client, i = args[i + 1], i + 2
        elif a == "--version":
            version, i = args[i + 1], i + 2
        elif a == "--hidden":
            hidden_too, i = True, i + 1
        elif a == "--top":
            top, i = int(args[i + 1]), i + 2
        else:
            words.append(a)
            i += 1
    if not words:
        sys.exit(__doc__)
    query = words_of(" ".join(words))
    clients = CLIENTS if client == "both" else (client,)

    now = {c: run_ids(ROOT, c, False) for c in clients}
    then, temp = None, None
    if version:
        if not version.startswith("v"):
            version = "v" + version
        temp, tree = tag_tree(version)
        own = not os.path.exists(os.path.join(tree, "Tools", "offline", "ids.lua"))
        then = {c: run_ids(tree, c, own) for c in clients}
        if not any(then[c][0] for c in clients):
            print("(%s can't be checked: that release has no /cine find ids list, so ids may not work there)"
                  % version)
            then = None

    # One line per id: which clients have it, and whether the player's release does.
    found = {}
    for c in clients:
        for id_, (page, label) in now[c][0].items():
            s = score(query, id_, page, label)
            if s:
                entry = found.setdefault(id_, {"score": s, "page": page, "label": label, "clients": []})
                entry["clients"].append(c)
    ranked = sorted(found.items(), key=lambda kv: (-kv[1]["score"], kv[0]))[:top]
    print("matches for %r (main, player copy Cinematic.toc)%s:" % (" ".join(words),
          (", checked against " + version) if then else ""))
    if not ranked:
        print("  none: try other words, or --hidden")
    for id_, e in ranked:
        where = "+".join(e["clients"]) if len(clients) > 1 else e["clients"][0]
        line = "  /cine find %-38s %-14s %-40s %s" % (id_, e["page"], e["label"][:40], where)
        if then:
            have = [c for c in e["clients"] if id_ in then[c][0]]
            line += "   in %s: %s" % (version, "yes" if len(have) == len(e["clients"]) else
                                       ("only " + "+".join(have) if have else
                                        "NO: added after it (they need to update; main-only = next update)"))
        print(line)

    if hidden_too:
        # (Not all are truly hidden: some are set by another control, as depthOfField by Camera haze's
        # dofScale slider, or by a grid cell. Read the code before giving a /run.)
        print("\nsettings with no /cine find id of their own (read the code: another control may set it;"
              " truly hidden = /run CinematicDB.<key>=<value> then /reload):")
        shown = 0
        seen = set()
        for c in clients:
            for key, (kind, default) in sorted(now[c][1].items()):
                if key in seen or not score(query, key, "", ""):
                    continue
                seen.add(key)
                shown += 1
                if shown <= top:
                    extra = ""
                    if then and key not in then[c][1] and key not in then[c][0]:
                        extra = "   NOT in " + version
                    print("  %-40s %-8s default %s%s" % (key, kind, default, extra))
        if not shown:
            print("  none")
    if temp:
        shutil.rmtree(temp, ignore_errors=True)


if __name__ == "__main__":
    main()
