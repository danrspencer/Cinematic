"""Refreshes the data in docs/design/profile-modules.html (the design review
of the profile modules) from the addon as it is now. From the repo root:

    python -I Tools/offline/design.py

Runs export.lua through run.py (no lua5.1 needed) and writes its JSON into
the page's <script id="data">, in the short keys the page reads.
"""
import json
import os
import re
import subprocess
import sys

PAGE = "docs/design/profile-modules.html"


def short_module(module):
    return {
        "k": module["key"], "n": module.get("name"), "t": module.get("tip"), "s": module.get("scope", []),
        "c": module.get("client"), "g": module.get("group"),
        "w": [[w.get("setting"), w.get("row"), w.get("value"), w.get("address")] for w in module.get("writes", [])],
    }


def short_profile(profile):
    return {
        "n": profile["name"], "l": profile.get("label"), "t": profile.get("tip"), "f": profile.get("from"),
        "h": profile.get("hidden", False), "listed": profile.get("listed", False),
        "m": [[m.get("key"), m.get("from")] for m in profile.get("modules", [])],
        "w": profile.get("writes", {}), "picks": profile.get("picks", {}),
    }


def short_client(data):
    return {
        "pages": [{"n": page["name"], "s": [[s["address"].split("/", 1)[1], s["settings"]]
                                                for s in page.get("sections", [])]}
                  for page in data.get("pages", [])],
        "modules": [short_module(m) for m in data.get("modules", [])],
        "profiles": [short_profile(p) for p in data.get("profiles", [])],
        "slots": data.get("slots", []),
        "levels": data.get("levels", []),
        "notes": data.get("notes", []),
    }


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    out = subprocess.run([sys.executable, "-I", os.path.join(here, "run.py"), "Tools/offline/export.lua"],
                         stdin=subprocess.DEVNULL, capture_output=True, text=True, encoding="utf-8")
    if out.returncode != 0:
        sys.exit(out.stderr or "export.lua failed")
    data = json.loads(out.stdout[out.stdout.index("{"):])
    blob = json.dumps({client: short_client(part) for client, part in data.items()},
                      ensure_ascii=False, separators=(",", ":")).replace("</", "<\\/")
    with open(PAGE, encoding="utf-8", newline="") as f:
        html = f.read()
    html, count = re.subn(r'(<script type="application/json" id="data">).*?(</script>)',
                          lambda m: m.group(1) + blob + m.group(2), html, count=1, flags=re.S)
    if count != 1:
        sys.exit("no data block in " + PAGE)
    with open(PAGE, "w", encoding="utf-8", newline="") as f:
        f.write(html)
    print("refreshed " + PAGE)


if __name__ == "__main__":
    main()
