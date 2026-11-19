"""Is the installed copy of an addon its latest release? For /addon-support.

    python -I .claude/skills/addon-support/latest_version.py <AddonName> [--github owner/repo]

Reads each client's installed .toc (version, X-Website, X-Curse-Project-ID,
X-Wago-ID, X-Github...) and, when it can find the addon's GitHub repository
(the toc's links, or --github), asks GitHub for its latest release (else its
newest tag). Sends only the repository's name; downloads no code.

Prints, per client: the installed version, the latest one, and BEHIND /
up to date / can't tell. Where GitHub isn't the source, prints the pages to
check by hand (CurseForge, Wago, the website).
Exit 0: every installed copy is the latest; 3: one is behind; 4: can't tell;
2: not installed.
"""
import json
import os
import re
import sys
import urllib.request

WOW = os.environ.get("CINE_WOW", r"C:\Program Files (x86)\World of Warcraft")
CLIENTS = ["_forever_", "_retail_", "_classic_era_"]
# Addons whose toc names no GitHub repository, but that release there (add
# one each time you find it, so the next run needs no --github).
KNOWN_REPOS = {
    "questie": "Questie/Questie",
    "rxpguides": "RestedXP/RXPGuides",
}

args = [a for a in sys.argv[1:] if not a.startswith("--")]
if not args:
    print(__doc__)
    sys.exit(1)
ADDON = args[0]
GITHUB = None
if "--github" in sys.argv:
    at = sys.argv.index("--github")
    GITHUB = sys.argv[at + 1] if at + 1 < len(sys.argv) else None


def read(path):
    with open(path, "rb") as f:
        data = f.read()
    try:
        return data.decode("utf-8-sig")
    except UnicodeDecodeError:
        return data.decode("latin-1")


def toc_meta(folder):
    meta = {}
    for toc in sorted(os.listdir(folder)):
        if toc.lower().endswith(".toc"):
            for line in read(os.path.join(folder, toc)).splitlines():
                m = re.match(r"##\s*([\w-]+)\s*:\s*(.*)", line)
                if m:
                    meta.setdefault(m.group(1).lower(), m.group(2).strip())
    return meta


def version_key(text):
    """Comparable form of a version: its first dotted number ("v1.2.10-beta" -> (1, 2, 10);
    "bundle/v12.11.1+v1.1.3" -> (12, 11, 1))."""
    m = re.search(r"\d+(?:\.\d+)*", text or "")
    return tuple(int(n) for n in m.group(0).split(".")) if m else ()


def github_repo(meta):
    for key, value in meta.items():
        m = re.search(r"github\.com[/:]([\w.-]+)/([\w.-]+?)(?:\.git)?(?:[/#?].*)?$", value)
        if m:
            return m.group(1) + "/" + m.group(2)
        if key in ("x-github", "x-github-repo") and re.fullmatch(r"[\w.-]+/[\w.-]+", value):
            return value
    return None


def fetch(url):
    """GitHub's JSON for url: straight, else through the gh CLI (a Python without the certificates)."""
    try:
        return fetch_direct(url)
    except Exception:
        import subprocess
        out = subprocess.run(["gh", "api", url.replace("https://api.github.com/", "")],
                             capture_output=True, text=True, timeout=30)
        if out.returncode != 0:
            raise RuntimeError(out.stderr.strip()[:200] or "gh api failed")
        return json.loads(out.stdout)


def fetch_direct(url):
    request = urllib.request.Request(url, headers={"User-Agent": "addon-version-check",
                                                   "Accept": "application/vnd.github+json"})
    with urllib.request.urlopen(request, timeout=15) as response:
        return json.loads(response.read().decode("utf-8"))


def latest_on_github(repo):
    """(version, where) of its newest release, else its newest tag; (None, why) when neither reads."""
    try:
        release = fetch("https://api.github.com/repos/%s/releases/latest" % repo)
        return release.get("tag_name") or release.get("name"), "release %s, %s" % (
            release.get("html_url"), (release.get("published_at") or "")[:10])
    except Exception as error:  # (No release: its tags.)
        first = error
    try:
        tags = fetch("https://api.github.com/repos/%s/tags?per_page=30" % repo)
        if tags:
            best = max(tags, key=lambda t: version_key(t.get("name")))
            return best.get("name"), "newest tag on github.com/%s" % repo
        return None, "github.com/%s has no releases or tags" % repo
    except Exception as error:
        return None, "GitHub unreadable (%s; %s)" % (first, error)


installs = []
for client in CLIENTS:
    base = os.path.join(WOW, client, "Interface", "AddOns")
    if os.path.isdir(base):
        for name in os.listdir(base):
            if name.lower() == ADDON.lower():
                installs.append((client, os.path.join(base, name)))
if not installs:
    print("%s: NOT INSTALLED in any client (%s). Ask the user to install it." % (ADDON, ", ".join(CLIENTS)))
    sys.exit(2)

metas = [(client, toc_meta(folder)) for client, folder in installs]
repo = GITHUB or KNOWN_REPOS.get(ADDON.lower())
for _, meta in metas:
    repo = repo or github_repo(meta)
latest, where = (None, "no GitHub repository in its toc (pass --github owner/repo if it has one)")
if repo:
    latest, where = latest_on_github(repo)

print("# %s: installed vs latest\n" % ADDON)
print("Latest: %s (%s)\n" % (latest or "?", where))
codes = []
for client, meta in metas:
    have = re.sub(r"^[vV]", "", meta.get("version", "?"))
    if not latest or not version_key(have):
        state, code = "CAN'T TELL", 4
    elif version_key(have) >= version_key(latest):
        state, code = "up to date", 0
    else:
        state, code = "BEHIND", 3
    codes.append(code)
    print("- %s: v%s, %s" % (client, have, state))
pages = []
for _, meta in metas:
    if meta.get("x-curse-project-id"):
        pages.append("CurseForge project %s (curseforge.com/wow/addons, search the id or the name)"
                     % meta["x-curse-project-id"])
    if meta.get("x-wago-id"):
        pages.append("https://addons.wago.io/addons/%s" % meta["x-wago-id"])
    if meta.get("x-website"):
        pages.append(meta["x-website"])
pages = list(dict.fromkeys(pages))
if pages:
    print("\nCheck by hand where GitHub isn't its source:\n" + "\n".join("- " + p for p in pages))
sys.exit(3 if 3 in codes else 4 if 4 in codes else 0)
