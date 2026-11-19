"""Static scan of another WoW addon, for writing Cinematic's support for it.

    python -I .claude/skills/addon-support/scan_addon.py <AddonName> [--all] [--libs]

Finds the addon in every installed client's Interface/AddOns (and its own
sub-addons: folders named <AddonName>_*), reads its .toc, Lua and XML, and
prints a Markdown report:

  1. where it is installed (clients, versions, website ids)
  2. frames it creates (named, built names, unnamed count), each named one
     marked handled or UNHANDLED against the Support file and its frame list
     (Tools/offline/addon-frames/<Support>.txt), as Tools/addon-check.py does
  3. game frames it touches (hides, reparents, hooks, lists), NEW ones first:
     "known" = the name already appears in Cinematic's Lua
  4. fade / hover traps (SetAlpha hooks with their bodies, its own fades,
     mouse toggles, ignore-parent-alpha, tiny holder frames)
  5. feature clashes (CVars it sets, camera, plates, chat, tooltip, minimap,
     quest tracker, UI hiding, cursor, edit mode...)
  6. taint risks (hooks on game code; secure code counted per file)

Only reads files; runs nothing from the addon. Embedded libraries (Libs/)
and Locales/ are skipped (--libs keeps libraries). Each list shows the first
12 hits unless --all. Exit 2: not installed anywhere.
"""
import importlib.util
import os
import re
import sys
from collections import OrderedDict, defaultdict

WOW = r"C:\Program Files (x86)\World of Warcraft"
CLIENTS = ["_forever_", "_retail_", "_classic_era_", "_classic_beta_", "_classic_era_ptr_"]
REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
LIMIT = 12

args = [a for a in sys.argv[1:] if not a.startswith("--")]
SHOW_ALL = "--all" in sys.argv
WITH_LIBS = "--libs" in sys.argv
if not args:
    print(__doc__)
    sys.exit(1)
ADDON = args[0]


def read(path):
    with open(path, "rb") as f:
        data = f.read()
    try:
        return data.decode("utf-8-sig")
    except UnicodeDecodeError:
        return data.decode("latin-1")


# ---------------------------------------------------------------- find it
installs = []  # (client, folder)
for client in CLIENTS:
    base = os.path.join(WOW, client, "Interface", "AddOns")
    if not os.path.isdir(base):
        continue
    for name in sorted(os.listdir(base)):
        if name.lower() == ADDON.lower() or name.lower().startswith(ADDON.lower() + "_"):
            installs.append((client, os.path.join(base, name)))

print(f"# Addon scan: {ADDON}\n")
if not installs:
    print("NOT INSTALLED in any client folder (" + ", ".join(CLIENTS) + ").")
    print("Ask the user to install it, then run this again.")
    sys.exit(2)

support_dir = os.path.join(REPO, "Support")
for f in sorted(os.listdir(support_dir)):
    if f.lower() == ADDON.lower() + ".lua":
        print(f"Cinematic already has Support/{f}: extend it, don't start over.\n")
    elif f.lower().startswith(ADDON.lower()) and f.endswith(".lua"):
        print(f"Cinematic has Support/{f} (related).\n")

print("## 1. Installed\n")
scan_dirs = OrderedDict()  # folder name -> path (the first client listed wins: Forever first)
for client, folder in installs:
    name = os.path.basename(folder)
    tocs = [t for t in os.listdir(folder) if t.lower().endswith(".toc")]
    meta = {}
    for toc in tocs:
        for line in read(os.path.join(folder, toc)).splitlines():
            m = re.match(r"##\s*(Interface|Version|Title|Dependencies|RequiredDeps|OptionalDeps|"
                         r"SavedVariables|SavedVariablesPerCharacter|X-Website|X-Curse-Project-ID|X-Wago-ID)\s*:\s*(.*)", line, re.I)
            if m:
                meta.setdefault(m.group(1), m.group(2).strip())
    title = re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", meta.get("Title", ""))
    print(f"- {client} {name}: v{meta.get('Version', '?')}, interface {meta.get('Interface', '?')}, "
          f"tocs {', '.join(tocs)}" + (f" ({title})" if title and title != name else ""))
    for key in ("Dependencies", "RequiredDeps", "OptionalDeps", "SavedVariables", "SavedVariablesPerCharacter",
                "X-Website", "X-Curse-Project-ID", "X-Wago-ID"):
        if key in meta:
            print(f"    {key}: {meta[key]}")
    scan_dirs.setdefault(name, folder)
print()

files = []
for name, folder in scan_dirs.items():
    for root, dirs, fnames in os.walk(folder):
        rel_root = os.path.relpath(root, folder).replace("\\", "/")
        if not WITH_LIBS and re.search(r"(^|/)(libs?|libraries|embeds)(/|$)", rel_root, re.I):
            continue
        if re.search(r"(^|/)locales?(/|$)", rel_root, re.I):
            continue
        for f in fnames:
            if f.lower().endswith((".lua", ".xml")):
                rel = name + "/" + ("" if rel_root == "." else rel_root + "/") + f
                files.append((rel, os.path.join(root, f)))
print(f"Scanned {len(files)} Lua/XML files from the first client listed per folder"
      + ("" if WITH_LIBS else " (Libs/ and Locales/ skipped)") + ".\n")

# Every identifier our own Lua mentions: a game frame we already handle.
ours = set()
for root, dirs, fnames in os.walk(REPO):
    dirs[:] = [d for d in dirs if d not in (".git", "Tools", "docs", "Locales", ".claude", "Media")]
    for f in fnames:
        if f.endswith(".lua"):
            ours.update(re.findall(r"[A-Za-z_][A-Za-z0-9_]{3,}", read(os.path.join(root, f))))

# ---------------------------------------------------------------- patterns
NOT_FIELD = r"(?<![\w.:\\])"  # not a field of something else, not inside a texture path
FRAME_WORDS = (r"[A-Z][A-Za-z0-9]*(?:Frame|Bar|Bars|Button|Container|Manager|Menu|Tracker|Viewer|Cluster|"
               r"Tooltip|Popup|Dock|Holder|Display|Banner|Alert|Toast)[A-Za-z0-9]*")
GAME_FRAME = (r"(?:_G\.|_G\[\s*[\"'])?(" + FRAME_WORDS +
              r"|Minimap|UIParent|WorldFrame|MicroMenu|BagsBar|DamageMeter|MultiBar\w+|ChatFrame\d+\w*)(?:[\"']\s*\])?")
CREATE = re.compile(r"(?:CreateFrame\s*\(|pcall\s*\(\s*CreateFrame\s*,)\s*([\"'][^\"']+[\"'])\s*(?:,\s*([^,\)]+))?")
XML_FRAME = re.compile(r"<(Frame|Button|StatusBar|ScrollFrame|CheckButton|Cooldown|PlayerModel|Slider|EditBox)\b"
                       r"[^>]*\bname=\"([^\"]+)\"", re.I)
GAME_CALL = re.compile(NOT_FIELD + GAME_FRAME + r"\s*[:.]\s*(Hide|Show|SetParent|SetAlpha|UnregisterAllEvents|"
                       r"UnregisterEvent|SetScale|ClearAllPoints|SetPoint|SetShown|EnableMouse|SetIgnoreParentAlpha|"
                       r"HookScript|SetScript)\b")
GAME_HOOK = re.compile(r"hooksecurefunc\s*\(\s*" + GAME_FRAME + r"\s*,\s*[\"'](\w+)[\"']")
GLOBAL_HOOK = re.compile(r"hooksecurefunc\s*\(\s*[\"'](\w+)[\"']")
DRIVER = re.compile(r"(RegisterStateDriver|RegisterAttributeDriver)\s*\(\s*" + GAME_FRAME + r"\s*,\s*[\"'](\w+)[\"']")
QUOTED = re.compile(r"[\"'](" + FRAME_WORDS + r"|MultiBar\w+|MicroMenu|BagsBar|DamageMeter|Minimap)[\"']")
NOT_A_FRAME = re.compile(r"Template\w*$|Texture$|Indices$|^(Set|Get|On|Show|Hide|Update|Should|Layout|Is|Has|Can|Toggle)[A-Z]")
ALPHA_HOOK = re.compile(r"hooksecurefunc\s*\([^,]+,\s*[\"']SetAlpha[\"']")

FADE = [
    (r"UIFrameFade(In|Out)\b", "UIFrameFadeIn/Out (its own fade)"),
    (r"SetIgnoreParentAlpha\s*\(\s*true", "SetIgnoreParentAlpha(true): ignores a faded parent"),
    (r"RegisterStateDriver\s*\([^,]+,\s*[\"']visibility[\"']", "visibility state driver: it shows/hides this itself"),
]
COUNTED = [
    (r":SetAlpha\s*\(\s*[a-zA-Z_][\w.]*\s*[\),]", "SetAlpha(variable)"),
    (r"(mouseover|Mouseover|MouseOver|fadeAlpha|inactiveAlpha|combatAlpha|showOnMouseover)", "fade/mouseover setting"),
    (r"Secure(Handler|Action|Unit|Group|Header)\w*Template|SecureHandler\w*", "secure template"),
    (r"\bRegisterStateDriver\b|\bRegisterAttributeDriver\b", "state/attribute driver"),
    (r":SetAttribute\s*\(", "SetAttribute"),
    (r"\bissecretvalue\b|\bcanaccessvalue\b", "secret-value check"),
    (r"InCombatLockdown\s*\(\s*\)", "InCombatLockdown check"),
]
HOVER = [
    (r"EnableMouse\s*\(\s*(false|(?!true\b)[a-zA-Z_][\w.]*)\s*\)",
     "EnableMouse(false/variable): may stop taking the mouse (hover by rect: ns.HOVER_BY_RECT)"),
    (r"SetMouseClickEnabled|SetMouseMotionEnabled|SetPropagateMouse", "partial mouse handling"),
    (r"SetSize\s*\(\s*(0?\.\d+|1)\s*,\s*(0?\.\d+|1)\s*\)", "1x1 holder: draws around itself (hover by children)"),
]
CVAR = re.compile(r"(?:SetCVar|C_CVar\.SetCVar)\s*\(\s*[\"']([A-Za-z_]\w*)[\"']")
CLASH = [
    ("camera", r"(SetView|SaveView|ResetView|MoveView\w+|CameraZoom\w+|SetCameraDistance|test_camera\w*|"
               r"ActionCam|cameraDistanceMax\w*|FlipCamera)\b"),
    ("ui hiding", r"(SetUIVisibility|UIParent:Hide|UIParent:SetAlpha|UIParent:SetScale)\b"),
    ("nameplates", r"(C_NamePlate\.\w+|NAME_PLATE_UNIT_ADDED|NamePlateDriverFrame)\b"),
    ("chat", r"(ChatFrame_AddMessageEventFilter|FCF_\w+|ChatFrame_OnHyperlinkShow)\b"),
    ("tooltip", r"(TooltipDataProcessor\.\w+|GameTooltip:HookScript|GameTooltip_SetDefaultAnchor)\b"),
    ("minimap", r"(Minimap:\w+|MinimapCluster|LibDBIcon|GetMinimapShape)\b"),
    ("quest tracker", r"(ObjectiveTrackerFrame|QuestWatchFrame|WatchFrame|C_QuestLog\.AddQuestWatch)\b"),
    ("dialogs", r"(GossipFrame|QuestFrame|TalkingHeadFrame|ImmersionFrame)\b"),
    ("cursor", r"(SetCursor|ResetCursor)\b"),
    ("screen text", r"(UIErrorsFrame:\w+|RaidWarningFrame|ActionStatus|LossOfControlFrame|ZoneTextFrame|SubZoneTextFrame)\b"),
    ("emotes/afk", r"(DoEmote|UnitIsAFK)\b"),
    ("screenshots", r"(Screenshot\(|SCREENSHOT_SUCCEEDED)"),
    ("edit mode", r"(EditModeManagerFrame|C_EditMode\.\w+|LibEditMode)\b"),
    ("cooldown manager", r"(EssentialCooldownViewer|UtilityCooldownViewer|BuffIconCooldownViewer|BuffBarCooldownViewer)\b"),
    ("bags", r"(ContainerFrame\w*|OpenAllBags|ToggleAllBags|C_Container\.UseContainerItem)\b"),
]

lists = defaultdict(list)            # bucket -> [(where, text)]
game_hits = defaultdict(list)        # game frame -> [(where, what)]
counts = defaultdict(int)            # (kind, file) -> hits
cvars = OrderedDict()                # cvar -> [where]
quoted = OrderedDict()               # frame-like name it only quotes (lists, _G[...]) -> first where


def add(bucket, where, text):
    lists[bucket].append((where, text))


for rel, path in files:
    text = read(path)
    lines = text.splitlines()
    if path.lower().endswith(".xml"):
        for i, line in enumerate(lines, 1):
            for m in XML_FRAME.finditer(line):
                add("named", f"{rel}:{i}", f"{m.group(1)} {m.group(2)}")
        continue
    in_block = False
    for i, line in enumerate(lines, 1):
        # (Comments out: block ones roughly, line ones exactly enough.)
        if in_block:
            if "]]" in line:
                in_block = False
            continue
        if line.lstrip().startswith("--[["):
            in_block = "]]" not in line
            continue
        code = re.sub(r"--.*$", "", line)
        if not code.strip():
            continue
        where = f"{rel}:{i}"
        short = code.strip()[:150]
        for m in CREATE.finditer(code):
            kind, name = m.group(1).strip("\"'"), (m.group(2) or "nil").strip()
            if name in ("nil", ""):
                counts[("unnamed CreateFrame", rel)] += 1
            elif re.fullmatch(r"[\"'][^\"']+[\"']", name):
                add("named", where, f"{kind} {name[1:-1]}")
            else:
                add("built", where, f"{kind} {name}: {short}")
        for m in GAME_CALL.finditer(code):
            game_hits[m.group(1)].append((where, ":" + m.group(2)))
        for m in GAME_HOOK.finditer(code):
            game_hits[m.group(1)].append((where, "hooksecurefunc " + m.group(2)))
            add("hooks", where, f"hooksecurefunc({m.group(1)}, \"{m.group(2)}\")")
        for m in GLOBAL_HOOK.finditer(code):
            add("hooks", where, f"hooksecurefunc(\"{m.group(1)}\")")
        for m in DRIVER.finditer(code):
            game_hits[m.group(2)].append((where, f"{m.group(1)} {m.group(3)}"))
        for m in QUOTED.finditer(code):
            name = m.group(1)
            if not NOT_A_FRAME.search(name) and not name.lower().startswith(ADDON.lower()):
                quoted.setdefault(name, where)
        if ALPHA_HOOK.search(code):
            body = [ln.strip()[:120] for ln in lines[i:i + 8] if ln.strip()]
            add("alphahooks", where, short + "".join("\n      " + b for b in body))
        for pattern, what in FADE:
            if re.search(pattern, code):
                add("fade", where, f"{what}: {short}")
        for pattern, what in HOVER:
            if re.search(pattern, code):
                add("hover", where, f"{what}: {short}")
        for pattern, what in COUNTED:
            if re.search(pattern, code):
                counts[(what, rel)] += 1
        for m in CVAR.finditer(code):
            cvars.setdefault(m.group(1), []).append(where)
        for label, pattern in CLASH:
            if re.search(NOT_FIELD + pattern, code) and not re.search(r"function\s+[\w.:]*" + pattern, code):
                add("clash:" + label, where, short)


def show(title, hits, hint=""):
    print(f"### {title} ({len(hits)})\n")
    if hint:
        print(hint + "\n")
    if not hits:
        print("none\n")
        return
    for where, what in (hits if SHOW_ALL else hits[:LIMIT]):
        print(f"- `{where}` {what}")
    if not SHOW_ALL and len(hits) > LIMIT:
        print(f"- ... {len(hits) - LIMIT} more (--all)")
    print()


def show_counts(title, kinds):
    rows = sorted(((k, f, n) for (k, f), n in counts.items() if k in kinds), key=lambda r: (r[0], -r[2]))
    print(f"### {title}\n")
    if not rows:
        print("none\n")
        return
    for kind, f, n in rows:
        print(f"- {kind}: {n} in `{f}`")
    print()


print("## 2. Frames it creates\n")
# Every named frame, as Tools/addon-check.py finds them (pcall(CreateFrame,
# ...) and built names read where it can: DaylightUI's buff bars were missed
# by a plain CreateFrame( search), each marked with how our side covers it.
spec = importlib.util.spec_from_file_location("addon_check", os.path.join(REPO, "Tools", "addon-check.py"))
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)
support_code, support_name = "", None
for each_name, each_code, each_addons, _ in check.support_files():
    if any(a.lower() == ADDON.lower() for a in each_addons):
        support_code, support_name = each_code, each_name
prefixes = {re.match(r"[A-Za-z][A-Za-z0-9]*", ADDON).group(0)} | set(check.EXTRA_PREFIXES.get(ADDON, []))
made = check.frames_made([(rel, read(path)) for rel, path in files], prefixes)
accounted = check.load_accounted(support_name) if support_name else None
# (Its frames not starting with its name: the plain search's list.)
for where, what in lists["named"]:
    made.setdefault(what.split(" ", 1)[1], where)
marks = {n: (check.handled_by(n, support_code, prefixes, accounted) if support_name else None) for n in made}
open_ones = [n for n in made if not marks[n]]
print(f"### Named ({len(made)}, {len(open_ones)} UNHANDLED)\n")
print("UNHANDLED = neither named by the Support file nor in Tools/offline/addon-frames/<Support>.txt: "
      "decide each one (a row, a fade area, or listed with why it needs none). * = a part of a built name "
      "that can't be read.\n")
for name in sorted(made, key=lambda n: (marks[n] is not None, n)):
    print(f"- {name} `{made[name]}` " + (f"({marks[name]})" if marks[name] else "**UNHANDLED**"))
print()
show("Built names (resolve each pattern: numbered, prefixed, from a variable)", lists["built"])
show_counts("Unnamed frames, by file (need a scanner or match() if they matter)", {"unnamed CreateFrame"})

print("## 3. Game frames it touches\n")
print("NEW = Cinematic's Lua never names it: check whether a row should cover it.\n")
print(f"### Acts on ({len(game_hits)})\n")
for name in sorted(game_hits, key=lambda n: (n in ours, n)):
    hits = game_hits[name]
    whats = sorted({w for _, w in hits})
    more = f" +{len(hits) - 1}" if len(hits) > 1 else ""
    print(f"- **{name}** {'known' if name in ours else 'NEW'}: {', '.join(whats)} (`{hits[0][0]}`{more})")
print()
for label, want in (("NEW", False), ("known", True)):
    names = [n for n in quoted if n not in game_hits and (n in ours) == want]
    print(f"### Only named in strings, {label} ({len(names)})\n")
    print("(lists it loops over, _G[...] lookups; some are its own module or field names)\n")
    print(", ".join(f"{n} `{quoted[n]}`" for n in names) or "none")
    print()

print("## 4. Fade / hover traps\n")
show("SetAlpha hooks, with the lines after", lists["alphahooks"],
     "Read each: a hook that turns the mouse off, or sets alpha back, fights our fade.")
show("Its own fades", lists["fade"])
show_counts("Own alpha work, by file", {"SetAlpha(variable)", "fade/mouseover setting"})
show("Mouse handling", lists["hover"])

print("## 5. Feature clashes\n")
print(f"### CVars it sets ({len(cvars)})\n")
for name, wheres in cvars.items():
    more = f" +{len(wheres) - 1}" if len(wheres) > 1 else ""
    print(f"- {name}{' (Cinematic touches it too)' if name in ours else ''} `{wheres[0]}`{more}")
print()
for label, _ in CLASH:
    hits = lists.get("clash:" + label)
    if hits:
        show("Area: " + label, hits)

print("## 6. Taint risks\n")
show("Hooks on game code", lists["hooks"])
show_counts("Secure code, by file", {"secure template", "state/attribute driver", "SetAttribute",
                                     "secret-value check", "InCombatLockdown check"})
