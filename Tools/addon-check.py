"""Other addons' updates against Cinematic's support for them. From the repo root:

    python -I Tools/addon-check.py            check every installed supported addon
    python -I Tools/addon-check.py --update   save what each one looks like now as the baseline

Two checks per Support file whose addon is installed (in any client: each
client's copy is read on its own, as their versions can differ):

1. Support still matches (FAIL): the names Support/<X>.lua relies on are still
   in the addon's code. Those are its frame and global names (string literals
   and _G.<name> starting with the addon's own name, built names' fixed parts
   too, like "DaylightUIBar" in "DaylightUIBar" .. n), the fields read off its
   global (_G.DaylightUI.Fade) and the methods hooked on its objects
   (hooksecurefunc(fade, "Register")). One gone = a rename or a removal that
   leaves our support doing nothing.
2. What changed (a note, never a FAIL): what breaks fades and hovers, read off
   the addon's code without line numbers: the frames it names, SetAlpha hooks,
   SetAlphaFromBoolean (a secret alpha: the DaylightUI party flicker,
   2026-11-19), SetIgnoreParentAlpha, mouse turned off, its own fades, state
   drivers, the CVars it sets and its hooks on game code, per file. Compared
   with Tools/offline/addon-baseline/<Support file>-<client>.txt; anything new
   is a cue to run /addon-support on it again, then --update.
3. Every frame covered (MISS, a failure): each named frame the addon makes
   (pcall(CreateFrame, ...) and built names too) is either named by the
   Support file or listed in Tools/offline/addon-frames/<Support file>.txt
   with why it needs no line there. Without that list: a note with the count.

Not installed: "----", skipped. Only reads files; runs nothing from the addons.
Exit 1 when a check 1 fails. The game's folder: CINE_WOW, else the default.
"""
import fnmatch
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WOW = os.environ.get("CINE_WOW", r"C:\Program Files (x86)\World of Warcraft")
CLIENTS = {"forever": "_forever_", "retail": "_retail_"}
BASELINE = os.path.join(ROOT, "Tools", "offline", "addon-baseline")
UPDATE = "--update" in sys.argv

# Frame name starts an addon uses besides its own name (none of these is
# installed yet: add one when a check misses its frames).
EXTRA_PREFIXES = {
    "Bartender4": ["BT4"],
    "ElvUI": ["ElvUF_", "ElvUI_"],
    # (Its parts' own short names: action bars EAB, resource bars ERB_, raid
    # frames ERF, cooldowns ECME_, cast line ECL_, minimap EWB_, meters EDM_,
    # data bars EDB_, window skins WSkin; Ellesmere for EllesmereEAB_ and the like.)
    "EllesmereUI": ["Ellesmere", "EUI", "EAB", "ERB_", "ERF", "ECME_", "ECL_", "EWB_", "EDM_", "EDB_", "WSkin"],
    # (Folder RXPGuides, frames RXPFrame, RXPG_ARROW...: without it the check
    # saw none of them, till 2026-11-19.)
    "RXPGuides": ["RXP"],
}
# Names a Support file mentions that are built in ways a text search can't
# find (left out of check 1): "<Support file>": {names}.
NOT_CHECKED = {}
# Methods a hook names that are the game's (on its frames), not the addon's.
GAME_METHOD = re.compile(r"^(Set|Get|Show|Hide|Clear|Enable|Disable|Is|Has|Register|Unregister|Hook|Create|"
                         r"Add|Remove|Release|Acquire)[A-Z]?|^On[A-Z]")


def read(path):
    with open(path, "rb") as f:
        data = f.read()
    try:
        return data.decode("utf-8-sig")
    except UnicodeDecodeError:
        return data.decode("latin-1")


def strip_comments(text):
    text = re.sub(r"--\[(=*)\[.*?\]\1\]", "", text, flags=re.S)
    return re.sub(r"--[^\n]*", "", text)


# ---------------------------------------------------------------- our side
def support_files():
    """Each Support file: the addon folder names it names, and its name prefixes."""
    out = []
    for fname in sorted(os.listdir(os.path.join(ROOT, "Support"))):
        if not fname.endswith(".lua"):
            continue
        code = strip_comments(read(os.path.join(ROOT, "Support", fname)))
        addons = set(re.findall(r"WhenAddonLoads\(\s*\"([^\"]+)\"", code))
        addons |= set(re.findall(r"\baddon\s*=\s*\"([^\"]+)\"", code))
        addons |= set(re.findall(r"\bknown\.addon\b[^=\n]*=\s*\"([^\"]+)\"", code))
        addons |= set(re.findall(r"IsAddOnLoaded\(\s*\"([^\"]+)\"", code))
        # (Its name in a local: local LABEL = "DynamicCam", then addon = LABEL.)
        for var, value in re.findall(r"local\s+(\w+)\s*=\s*\"([^\"]+)\"", code):
            if re.search(r"(\baddon\s*=\s*|WhenAddonLoads\(\s*)" + var + r"\b", code):
                addons.add(value)
        if not addons:
            continue
        prefixes = set()
        for addon in addons:
            head = re.match(r"[A-Za-z][A-Za-z0-9]*", addon)
            if head and len(head.group(0)) >= 3:
                prefixes.add(head.group(0))
            prefixes.update(EXTRA_PREFIXES.get(addon, []))
        out.append((fname[:-4], code, addons, prefixes))
    return out


def expected(code, addons, prefixes, skip):
    """What a Support file relies on: ("name", x), ("field", x), ("method", x)."""
    wants = set()
    starts = tuple(prefixes)
    for literal in re.findall(r"\"([A-Za-z_][A-Za-z0-9_]*)\"", code):
        if literal.startswith(starts) and literal not in addons and literal not in prefixes:
            wants.add(("name", literal))
    for chain in re.findall(r"_G\.([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)", code):
        parts = chain.split(".")
        if not parts[0].startswith(starts):
            continue
        if parts[0] not in addons and parts[0] not in prefixes:
            wants.add(("name", parts[0]))
        for field in parts[1:]:
            wants.add(("field", field))
    for method in re.findall(r"hooksecurefunc\(\s*[A-Za-z_][\w.]*\s*,\s*\"(\w+)\"", code):
        if not GAME_METHOD.match(method):
            wants.add(("method", method))
    return {w for w in wants if w[1] not in skip}


# ---------------------------------------------------------------- their side
def installed(client_dir, addons):
    """Its folders in one client: each named addon, and its sub-addons (<name>_*)."""
    base = os.path.join(WOW, client_dir, "Interface", "AddOns")
    if not os.path.isdir(base):
        return []
    found = []
    names = {a.lower() for a in addons}
    for folder in sorted(os.listdir(base)):
        low = folder.lower()
        if low in names or any(low.startswith(n + "_") for n in names):
            found.append(os.path.join(base, folder))
    return found


def version_of(folders):
    versions = set()
    for folder in folders:
        for toc in os.listdir(folder):
            if toc.lower().endswith(".toc"):
                m = re.search(r"^##\s*Version\s*:\s*(.+)$", read(os.path.join(folder, toc)), re.M)
                if m:
                    versions.add(m.group(1).strip())
    return ", ".join(sorted(versions)) or "?"


def sources(folders):
    """(relative path, text) of every Lua and XML file in the folders, Libs too."""
    out = []
    for folder in folders:
        name = os.path.basename(folder)
        for root, _, fnames in os.walk(folder):
            for f in fnames:
                if f.lower().endswith((".lua", ".xml")):
                    path = os.path.join(root, f)
                    rel = name + "/" + os.path.relpath(path, folder).replace("\\", "/")
                    out.append((rel, read(path)))
    return out


BUILT = re.compile(r"[\"']([A-Za-z_][A-Za-z0-9_]{5,})[\"']\s*\.\.")


def found(want, texts, built):
    kind, word = want
    if kind == "name":
        # (Or built: a fixed start joined to the rest, "DaylightUICastBar_" .. unit.)
        return any(word in t for t in texts) or any(word.startswith(b) for b in built)
    pattern = re.compile(r"[.:]" + word + r"\b|\b" + word + r"\s*=|\[\s*[\"']" + word + r"[\"']\s*\]")
    return any(pattern.search(t) for t in texts)


# ---------------------------------------------------------------- every frame it makes
# Every named frame the addon makes, however it makes it: CreateFrame("T",
# "Name"), through pcall (pcall(CreateFrame, "T", "Name"): DaylightUI's buff
# bars, missed till 2026-11-19), XML name=, and built names. A built name's
# parts are read where they can be: a string, or a field set to a string
# somewhere in the addon (frameName = "DaylightUIBuffs", then
# self.frameName .. "Holder"); any other part is a *.
MAKE_CALL = re.compile(r"(?:\bCreateFrame\s*\(|\bpcall\s*\(\s*CreateFrame\s*,)\s*")
FIELD_SET = re.compile(r"(?:\.|\b)([A-Za-z_]\w*)\s*=\s*[\"']([A-Za-z_]\w*)[\"']")
STRING = re.compile(r"^[\"']([^\"']*)[\"']$")
FIELD = re.compile(r"^[A-Za-z_][\w]*(?:\.[A-Za-z_]\w*)+$|^[A-Z][A-Z0-9_]+$")


def call_args(code, start):
    """The arguments of the call opening at start, split at top-level commas."""
    args, depth, cur, i, quote = [], 0, [], start, None
    while i < len(code):
        ch = code[i]
        if quote:
            cur.append(ch)
            if ch == "\\":
                cur.append(code[i + 1:i + 2])
                i += 1
            elif ch == quote:
                quote = None
        elif ch in "\"'":
            quote = ch
            cur.append(ch)
        elif ch in "([{":
            depth += 1
            cur.append(ch)
        elif ch in ")]}":
            if depth == 0:
                args.append("".join(cur).strip())
                return args
            depth -= 1
            cur.append(ch)
        elif ch == "," and depth == 0:
            args.append("".join(cur).strip())
            cur = []
        else:
            cur.append(ch)
        i += 1
    return args


def name_patterns(expr, fields, starts):
    """The names an expression can build: plain names, or globs with * for what can't be read."""
    if expr in ("", "nil"):
        return []
    outs = [""]
    for piece in re.split(r"\s*\.\.\s*", expr):
        m = STRING.match(piece)
        if m:
            choices = [m.group(1)]
        else:
            last = piece.split(".")[-1]
            values = fields.get(last, ())
            # (Only a field set to a few of its own names: a plain local like
            # name, set to anything anywhere, is a *.)
            if FIELD.match(piece) and 0 < len(values) <= 4 and all(v.startswith(starts) for v in values):
                choices = sorted(values)
            else:
                choices = ["*"]
        outs = [o + c for o in outs for c in choices]
    return [re.sub(r"\*+", "*", o) for o in outs if o.startswith(starts)]


def frames_made(files, prefixes):
    """{name or glob: first file:line} of every named frame it makes (Libs left out)."""
    starts = tuple(prefixes)
    fields = {}
    codes = []
    for rel, text in files:
        if re.search(r"/(libs?|libraries|embeds|locales?)/", rel, re.I):
            continue
        if rel.lower().endswith(".xml"):
            codes.append((rel, text, True))
            continue
        code = strip_comments(text)
        codes.append((rel, code, False))
        for field, value in FIELD_SET.findall(code):
            fields.setdefault(field, set()).add(value)
    made = {}
    # (Templates first, from every XML file: a frame made from one gets its
    # $parent children, in XML or by CreateFrame's template argument.)
    templates = {}
    for rel, code, xml in codes:
        if xml:
            xml_frames(rel, code, starts, templates, None)
    for rel, code, xml in codes:
        if xml:
            xml_frames(rel, code, starts, templates, made)
            continue
        for m in MAKE_CALL.finditer(code):
            args = call_args(code, m.end())
            if len(args) < 2:
                continue
            where = "%s:%d" % (rel, code.count("\n", 0, m.start()) + 1)
            inherits = STRING.match(args[3]) if len(args) > 3 else None
            # (The name, or "a and b or nil": each side that could be one.)
            for expr in re.split(r"\s+and\s+|\s+or\s+", args[1]):
                for name in name_patterns(expr.strip(), fields, starts):
                    made.setdefault(name, where)
                    for template in (inherits.group(1).split(",") if inherits else ()):
                        for child in templates.get(template.strip(), ()):
                            made.setdefault(name + child, where + " (its template's)")
    return made


# XML frames, nested: a name with $parent is its parent frame's name and the
# rest ("$parentBar" in DaylightUIFrame = DaylightUIFrameBar), missed while
# only whole names were read (till 2026-11-19). A virtual frame is a
# template: its $parent children are kept (templates: name -> suffixes) and
# added to each frame made from it.
XML_TAG = re.compile(r"<(/?)([A-Za-z]\w*)\b([^>]*?)(/?)>", re.S)
XML_FRAME_TAGS = {"frame", "button", "statusbar", "scrollframe", "checkbutton", "cooldown", "playermodel",
                  "slider", "editbox", "model", "modelscene", "messageframe", "scrollingmessageframe",
                  "simplehtml", "colorselect", "gametooltip", "dressupmodel", "cinematicmodel", "tabardmodel"}
VIRTUAL = re.compile(r"\bvirtual=\"true\"", re.I)


def xml_frames(rel, text, starts, templates, made):
    """made None: collect its templates' $parent children. Else add each named frame to made."""
    text = re.sub(r"<!--.*?-->", lambda c: "\n" * c.group(0).count("\n"), text, flags=re.S)
    stack = []  # (tag, resolved name or None, virtual, template it's inside or None)
    for m in XML_TAG.finditer(text):
        closing, tag, attrs, self_closing = m.group(1), m.group(2).lower(), m.group(3), m.group(4)
        if closing:
            while stack:
                if stack.pop()[0] == tag:
                    break
            continue
        is_frame = tag in XML_FRAME_TAGS
        raw = re.search(r"\bname=\"([^\"]+)\"", attrs) if is_frame else None
        own_virtual = bool(VIRTUAL.search(attrs))
        virtual = own_virtual or any(e[2] for e in stack)
        parent = next((e[1] for e in reversed(stack) if e[1]), None)
        template = next((e[3] for e in reversed(stack) if e[3]), None)
        name = None
        if raw:
            name = raw.group(1)
            if "$" in name:
                name = re.sub(r"\$parent", lambda _: parent, name, flags=re.I) if parent else None
        if raw and own_virtual and "$" not in raw.group(1):
            template = raw.group(1)
            templates.setdefault(template, set())
        elif raw and made is None and template and name and name.startswith(template):
            # (A child of a template: its name past the template's.)
            templates[template].add(name[len(template):])
        if made is not None and name and not virtual and name.startswith(starts):
            where = "%s:%d" % (rel, text.count("\n", 0, m.start()) + 1)
            made.setdefault(name, where)
            for inherit in re.findall(r"\binherits=\"([^\"]+)\"", attrs):
                for each in inherit.split(","):
                    for child in templates.get(each.strip(), ()):
                        made.setdefault(name + child, where + " (its template's)")
        if not self_closing:
            stack.append((tag, name if is_frame else None, virtual, template))


def accounted_path(support):
    return os.path.join(ROOT, "Tools", "offline", "addon-frames", support + ".txt")


def load_accounted(support):
    """Its frames the Support file doesn't name, each with why: {name or glob: why}, or None."""
    path = accounted_path(support)
    if not os.path.exists(path):
        return None
    out = {}
    for line in read(path).splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            name, _, why = line.partition(" ")
            out[name] = why.strip()
    return out


def handled_by(name, code, prefixes, accounted):
    """How our side covers a frame it makes: the Support file names it, or the list says why. None: nothing does."""
    literals = set(re.findall(r"\"([A-Za-z_][A-Za-z0-9_]*)\"", code))
    # (Starts it joins to the rest, "DaylightUIBar" .. n, or Lua patterns,
    # "^DaylightUIMeterWindow_": not the bare prefix, which would be all.)
    starts = set(re.findall(r"\"([A-Za-z_][A-Za-z0-9_]*)\"\s*\.\.", code))
    starts |= set(re.findall(r"\"\^([A-Za-z_][A-Za-z0-9_]*)", code))
    starts = {s for s in starts if not any(s.startswith(p) and len(s) < len(p) + 3 for p in prefixes)}
    head = name.split("*")[0]
    if name in literals:
        return "named"
    if "*" in name and any(fnmatch.fnmatchcase(l, name) for l in literals):
        return "named"
    # (Only a name it builds too: "DaylightUIBar" .. n covers
    # DaylightUIBar*Button*, not DaylightUIBarKeys.)
    if "*" in name and any(head.startswith(s) for s in starts):
        return "built"
    for pattern, why in (accounted or {}).items():
        # (A glob it builds is matched whole: ECME_TBB* in the list isn't
        # ECME_TBBWrap*, another frame.)
        if name == pattern or ("*" not in name and fnmatch.fnmatchcase(name, pattern)):
            return why or "listed"
    return None


# What the snapshot keeps, per file of the addon (Libs and Locales left out:
# what a library does is the same in every addon that has it).
FACTS = [
    (r"hooksecurefunc\s*\([^,]+,\s*[\"']SetAlpha[\"']", "SetAlpha hook"),
    (r"SetAlphaFromBoolean\s*\(", "SetAlphaFromBoolean (secret alpha)"),
    (r"SetIgnoreParentAlpha\s*\(\s*true", "SetIgnoreParentAlpha(true)"),
    (r"EnableMouse\s*\(\s*(false|(?!true\b)[A-Za-z_][\w.]*)\s*\)", "EnableMouse(false or a variable)"),
    (r"SetMouseClickEnabled|SetMouseMotionEnabled|SetPropagateMouse", "partial mouse handling"),
    (r"UIFrameFade(In|Out)\b", "UIFrameFadeIn/Out"),
    (r"\bRegisterStateDriver\b|\bRegisterAttributeDriver\b", "state driver"),
]
CREATE = re.compile(r"CreateFrame\s*\(\s*[\"'][^\"']+[\"']\s*,\s*[\"']([^\"']+)[\"']")
XML_NAME = re.compile(r"<(?:Frame|Button|StatusBar|ScrollFrame|CheckButton|Cooldown|PlayerModel|Slider|EditBox)\b"
                      r"[^>]*\bname=\"([^\"$]+)\"", re.I)
CVAR = re.compile(r"(?:SetCVar|C_CVar\.SetCVar)\s*\(\s*[\"']([A-Za-z_]\w*)[\"']")
GAME_HOOK = re.compile(r"hooksecurefunc\s*\(\s*(?:_G\.)?([A-Z]\w*)\s*,\s*[\"'](\w+)[\"']|"
                       r"hooksecurefunc\s*\(\s*[\"'](\w+)[\"']")


def snapshot(files):
    facts = set()
    for rel, text in files:
        if re.search(r"/(libs?|libraries|embeds|locales?)/", rel, re.I):
            continue
        if rel.lower().endswith(".xml"):
            facts.update("frame " + n for n in XML_NAME.findall(text))
            continue
        code = strip_comments(text)
        for pattern, what in FACTS:
            if re.search(pattern, code):
                facts.add("%s in %s" % (what, rel))
        facts.update("frame " + n for n in CREATE.findall(code))
        facts.update("sets CVar " + n for n in CVAR.findall(code))
        for target, method, global_fn in GAME_HOOK.findall(code):
            facts.add("hooks %s" % (global_fn or "%s:%s" % (target, method)))
    return facts


def baseline_path(support, client):
    return os.path.join(BASELINE, "%s-%s.txt" % (support, client))


def load_baseline(path):
    if not os.path.exists(path):
        return None, set()
    lines = read(path).splitlines()
    version = lines[0][len("# version "):] if lines and lines[0].startswith("# version ") else "?"
    return version, {l for l in lines[1:] if l.strip()}


def main():
    failed, changed, checked = 0, 0, 0
    supports = support_files()
    for support, code, addons, prefixes in supports:
        wants = expected(code, addons, prefixes, NOT_CHECKED.get(support, set()))
        any_client = False
        for client, client_dir in CLIENTS.items():
            folders = installed(client_dir, addons)
            if not folders:
                continue
            any_client = True
            checked += 1
            version = version_of(folders)
            files = sources(folders)
            texts = [t for _, t in files]
            # (Not the addon's bare name: "DaylightUI" .. key would match any name of it.)
            built = {b for t in texts for b in BUILT.findall(t)
                     if not any(b.startswith(p) and len(b) < len(p) + 3 for p in prefixes)}
            missing = sorted(w for w in wants if not found(w, texts, built))
            label = "%s on %s (v%s)" % (support, client, version)
            if missing:
                failed += 1
                print("FAIL  %s: Support/%s.lua expects %d gone: %s" % (label, support, len(missing),
                      ", ".join("%s %s" % w for w in missing[:12])))
            else:
                print("PASS  %s: all %d names Support/%s.lua uses are there" % (label, len(wants), support))
            # 3. Every named frame it makes is covered: named by the Support
            # file, or in its frame list with why (on screen through a fade
            # area, a window, a preview...). One missing = a frame nobody
            # looked at, as DaylightUI's buff popout was. A FAIL once the
            # Support file has a list; a note till then.
            # (Support files for the same addon cover its frames together, as
            # Questie's three do, and share their frame lists.)
            made = frames_made(files, prefixes)
            together = [s for s in supports if s[2] & addons]
            all_code = "\n".join(s[1] for s in together)
            lists = [load_accounted(s[0]) for s in together]
            accounted = None if all(l is None for l in lists) else {k: v for l in lists if l for k, v in l.items()}
            missing = sorted(n for n in made if not handled_by(n, all_code, prefixes, accounted))
            if missing and accounted is not None:
                failed += 1
                print("MISS  %s: %d frames it makes, none of them covered (add to Support/%s.lua, or to "
                      "Tools/offline/addon-frames/%s.txt with why):" % (label, len(missing), support, support))
                for name in missing:
                    print("      %s  %s" % (name, made[name]))
            elif missing:
                print("NOTE  %s: %d of its %d named frames aren't named by Support/%s.lua and it has no "
                      "frame list (Tools/offline/addon-frames/%s.txt)" % (label, len(missing), len(made),
                                                                          support, support))
            else:
                print("      every one of its %d named frames is covered" % len(made))
            facts = snapshot(files) | {"frame " + n for n in made}
            path = baseline_path(support, client)
            old_version, old = load_baseline(path)
            if UPDATE:
                os.makedirs(BASELINE, exist_ok=True)
                with open(path, "w", encoding="utf-8", newline="\n") as f:
                    f.write("# version %s\n" % version + "".join(l + "\n" for l in sorted(facts)))
                print("      baseline saved (%d facts)" % len(facts))
            elif old_version is None:
                print("NOTE  %s: no baseline yet (run with --update)" % label)
                changed += 1
            else:
                new, gone = sorted(facts - old), sorted(old - facts)
                if new or gone:
                    changed += 1
                    print("NOTE  %s: changed since v%s, %d new, %d gone (run /addon-support %s, then --update)"
                          % (label, old_version, len(new), len(gone), support))
                    for line in new[:15]:
                        print("      + " + line)
                    if len(new) > 15:
                        print("      + ... %d more" % (len(new) - 15))
                    for line in gone[:5]:
                        print("      - " + line)
                elif old_version != version:
                    print("      v%s to v%s: nothing new that touches fades or hovers" % (old_version, version))
        if not any_client:
            print("----  %s: not installed" % support)
    print("addon check: %d installed, %d FAILED, %d changed" % (checked, failed, changed))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
