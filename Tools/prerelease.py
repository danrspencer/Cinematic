"""Every check that runs outside the game, before a release, in one go. From
the repo root:

    python -I Tools/prerelease.py            all of it (about 4 minutes)
    python -I Tools/prerelease.py --game     only the in-game runs' results

Runs side by side, each a PASS or FAIL line, then one line for all of it:
- luacheck (baseline 0 warnings) and the Lua 5.1 compile of every .lua (the
  200-local cap and syntax, which luacheck misses);
- check-toc.py (dev TOC = release TOC + dev files, packaging);
- local-room.py: files near Lua's 200-local cap (named, never a FAIL);
- the full offline check (Tools/offline/check.lua: the profile modules, the
  built-in profiles' settings, setting ids);
- the settings sweep on the stand-in game, both clients
  (Tools/offline/sweep.lua: new FAIL lines against its baseline);
- the once-only settings updates on your own saved settings (each client's
  Cinematic.lua and CinematicDev.lua, a copy: nothing is written there),
  every update run from scratch: none may error;
- the upgrade check (Tools/upgrade-check.py): the last release's code and
  this one's on the same players' saved settings; what changes for existing
  players is listed (never a FAIL: the review judges it), only a version
  that doesn't load or an update that errors fails;
- the offline tests of fixed bugs (OFFLINE_TESTS: no FAIL line);
- other addons as installed against Support/ (Tools/addon-check.py: a name
  our support uses gone fails; what changed since its baseline is listed).
Then the last /cine prerelease runs on each client, read from the dev
copy's saved settings (after a /reload): their summary and NEW FAIL lines.

Exit 1 on any FAIL. Needs lupa (pip install lupa) and luacheck in ~/bin.
The game's folder: CINE_WOW, else C:/Program Files (x86)/World of Warcraft.
"""
import glob
import os
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WOW = os.environ.get("CINE_WOW", r"C:\Program Files (x86)\World of Warcraft")
CLIENTS = {"forever": "_forever_", "retail": "_retail_"}
PY = sys.executable
HOME = os.path.expanduser("~")
# Offline tests of one fixed bug each, PASS/FAIL per check (any FAIL line fails it).
OFFLINE_TESTS = [
    ("party flicker (DaylightUI range fade)", "Tools/offline/partyflicker.lua"),
    ("card wait (Rested card behind DaylightUI's zone title)", "Tools/offline/cardwait.lua"),
    ("loops off with their page off; page building waits for /cine debug loops", "Tools/offline/loopsoff.lua"),
    ("tooltip Location row (zone apart from class)", "Tools/offline/tooltiplocation.lua"),
    ("You level up card: Cheer, Congratulate, Commend", "Tools/offline/youlevelemotes.lua"),
    ("Cooldown Manager numbered lines (in place of situations)", "Tools/offline/cooldownlines.lua"),
    ("cast bar other kind's look, forever", "Tools/offline/castlook.lua", "forever"),
    ("cast bar other kind's look, retail", "Tools/offline/castlook.lua", "retail"),
    ("Mac notch covers, forever", "Tools/offline/notchgap.lua", "forever"),
    ("Mac notch covers, retail", "Tools/offline/notchgap.lua", "retail"),
    ("XP text font per character at login", "Tools/offline/xpfont.lua"),
    ("music volume never kept near 0", "Tools/offline/musicvolume.lua"),
    ("chat lines-only peeks only with the game's own chat", "Tools/offline/chatdefault.lua"),
    ("combat text keeps the game's numbers as its rows say", "Tools/offline/combattextkeep.lua"),
    ("reloads through a secure /reload on Forever, forever", "Tools/offline/reload.lua", "forever"),
    ("reloads as before on retail, retail", "Tools/offline/reload.lua", "retail"),
    ("detached parts follow our fade (FlareUI's gryphons)", "Tools/offline/gryphons.lua"),
    ("loose parts survey (/cine debug loose) finds exactly the detached parts", "Tools/offline/loosesurvey.lua"),
]


def lua_files():
    out = subprocess.run(["git", "ls-files", "--cached", "--others", "--exclude-standard", "*.lua"],
                         cwd=ROOT, capture_output=True, text=True).stdout.split()
    return [f for f in out if not f.startswith((".claude/", "Release/")) and os.path.exists(os.path.join(ROOT, f))]


def saved_files(client, name):
    pattern = os.path.join(WOW, CLIENTS[client], "WTF", "Account", "*", "SavedVariables", name)
    return sorted(glob.glob(pattern))


class Job:
    """One check as a process: its name, command, and how to read its output."""

    def __init__(self, name, cmd, judge=None):
        self.name, self.cmd, self.judge = name, cmd, judge
        self.started = time.time()
        self.proc = subprocess.Popen(cmd, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                     stdin=subprocess.DEVNULL, text=True, encoding="utf-8", errors="replace")

    def finish(self):
        output, _ = self.proc.communicate()
        self.seconds = time.time() - self.started
        ok = self.proc.returncode == 0
        detail = ""
        if self.judge:
            ok, detail = self.judge(ok, output)
        self.ok, self.output, self.detail = ok, output, detail
        return self


def last_line(output, starts=None):
    lines = [l for l in output.strip().splitlines() if l.strip()]
    if starts:
        lines = [l for l in lines if l.startswith(starts)] or lines
    return lines[-1].strip() if lines else ""


def judge_luacheck(ok, output):
    total = last_line(output, "Total:")
    return ok and "0 warnings / 0 errors" in total, total


def judge_compile(ok, output):
    bad = [l for l in output.splitlines() if l.strip() and not l.rstrip().endswith(" ok")]
    return ok and not bad, ("%d files ok" % len(output.splitlines())) if not bad else "; ".join(bad[:5])


def judge_room(ok, output):
    # (Never a FAIL by itself: a file at the cap still loads. Each tight one is
    # named, so a session adding locals there sees it; a file that doesn't
    # compile fails here and in the compile above.)
    tight = [l.strip() for l in output.splitlines() if l[:3].strip().isdigit()]
    detail = last_line(output, "local room:")
    if tight:
        detail += "\n      " + "\n      ".join(tight)
    return ok, detail


def judge_check(ok, output):
    line = last_line(output, "profile modules:")
    return ok and "0 problems" in line, line


def judge_sweep(ok, output):
    lines = output.strip().splitlines()
    new = [l.strip() for l in lines if l.strip().startswith("NEW ")]
    summary = last_line(output, "sweep ")
    detail = summary + ("".join("\n      " + l[:220] for l in new[:8]) if new else "")
    return ok, detail


def judge_test(ok, output):
    lines = [l.strip() for l in output.splitlines()]
    failed = [l for l in lines if l.startswith("FAIL ")]
    passed = sum(1 for l in lines if l.startswith("PASS "))
    if failed or not ok:
        return False, "; ".join(failed[:4]) or last_line(output)
    return passed > 0, "%d checks passed" % passed


def judge_addons(ok, output):
    lines = output.splitlines()
    shown = [l.strip() for l in lines if l.startswith(("FAIL", "MISS", "NOTE", "      +", "      -"))]
    detail = last_line(output, "addon check:")
    return ok, detail + "".join("\n      " + l[:220] for l in shown[:16])


def judge_migrate(ok, output):
    failed = [l for l in output.splitlines() if l.startswith("update failed")]
    if failed:
        return False, "; ".join(failed[:3])
    line = last_line(output)
    return ok, line.split(" lines written")[0] + " lines" if " lines written" in line else line


def judge_upgrade(ok, output):
    lines = output.splitlines()
    shown = [l.strip() for l in lines if l.startswith(("  CHANGED", "  NEW ON", "  NEW ", "  DROPPED", "  DEFAULT",
                                                        "  TYPE", "  RELOAD", "  FALLBACK", "FAIL"))]
    detail = last_line(output, "upgrade check:")
    return ok, detail + "".join("\n      " + l[:220] for l in shown[:30])


def game_results():
    """The last /cine prerelease runs per client and kind, from the dev copy's saved settings."""
    try:
        import lupa.lua51 as lua51
    except ImportError:
        return [("in-game runs", None, "lupa isn't installed (pip install lupa)")]
    rows = []
    for client in CLIENTS:
        files = saved_files(client, "CinematicDev.lua")
        if not files:
            rows.append(("in game, %s" % client, None, "no CinematicDev.lua saved settings found"))
            continue
        for path in files:
            lua = lua51.LuaRuntime(unpack_returned_tuples=True)
            env = lua.eval("{}")
            chunk = lua.eval("function(text, env) local f = assert(loadstring(text)) setfenv(f, env) f() end")
            with open(path, encoding="utf-8", errors="replace") as f:
                chunk(f.read(), env)
            db = env["CinematicDB"]
            store = db and db["prerelease"]
            runs = store and store[client]
            if not runs or len(runs) == 0:
                rows.append(("in game, %s" % client, None, "no /cine prerelease run yet"))
                continue
            latest = {}
            for i in range(1, len(runs) + 1):
                latest[runs[i]["kind"]] = runs[i]
            for kind in ("full", "quick", "guided"):
                each = latest.get(kind)
                if not each:
                    continue
                new = each["new"]
                names = [new[i] for i in range(1, len(new) + 1)] if new else []
                results = each["results"]
                lines = []
                for name in names[:10]:
                    detail = results[name] and results[name]["detail"]
                    lines.append("NEW FAIL %s%s" % (name, (": " + str(detail)[:160]) if detail else ""))
                ok = bool(each["finished"]) and not names
                detail = "%s (%s)" % (each["summary"], each["when"]) + "".join("\n      " + l for l in lines)
                rows.append(("in game, %s, %s" % (client, kind), ok, detail))
    return rows


def main():
    only_game = "--game" in sys.argv
    jobs = []
    if not only_game:
        lua = [PY, "-I", "Tools/offline/run.py"]
        luacheck = os.path.join(HOME, "bin", "luacheck.exe")
        jobs.append(Job("luacheck", [luacheck, "."], judge_luacheck))
        jobs.append(Job("Lua 5.1 compile", [PY, os.path.join(HOME, "bin", "luacompile.py")] + lua_files(),
                        judge_compile))
        jobs.append(Job("TOCs", [PY, "-I", "Tools/check-toc.py"], lambda ok, out: (ok, last_line(out))))
        jobs.append(Job("locals to spare (Lua's 200 cap)", [PY, "-I", "Tools/local-room.py"], judge_room))
        jobs.append(Job("offline check (profiles, ids)", lua + ["Tools/offline/check.lua"], judge_check))
        for client in CLIENTS:
            jobs.append(Job("offline sweep, %s" % client, lua + ["Tools/offline/sweep.lua", client], judge_sweep))
        for name, script, *args in OFFLINE_TESTS:
            jobs.append(Job(name, lua + [script] + args, judge_test))
        jobs.append(Job("upgrade check (existing players' settings)", [PY, "-I", "Tools/upgrade-check.py"],
                        judge_upgrade))
        jobs.append(Job("other addons vs our support", [PY, "-I", "Tools/addon-check.py"], judge_addons))
        scratch = tempfile.mkdtemp(prefix="cine-prerelease-")
        for client in CLIENTS:
            for name, toc in (("Cinematic.lua", "Cinematic.toc"), ("CinematicDev.lua", "CinematicDev.toc")):
                for path in saved_files(client, name):
                    out = os.path.join(scratch, "%s-%s.txt" % (client, name))
                    jobs.append(Job("updates on your %s %s" % (client, name),
                                    lua + ["Tools/offline/migrate-test.lua", client, toc, path, out], judge_migrate))
        print("prerelease: %d checks running side by side (the offline check takes a few minutes)..." % len(jobs))
        sys.stdout.flush()

    failed = 0
    for job in jobs:
        job.finish()
        mark = "PASS" if job.ok else "FAIL"
        failed += 0 if job.ok else 1
        print("%s  %s (%.0f s): %s" % (mark, job.name, job.seconds, job.detail))
        if not job.ok and not job.detail:
            print("      " + "\n      ".join(job.output.strip().splitlines()[-8:]))
    if not only_game:
        shutil.rmtree(scratch, ignore_errors=True)
    for name, ok, detail in game_results():
        mark = "PASS" if ok else ("----" if ok is None else "FAIL")
        failed += 1 if ok is False else 0
        print("%s  %s: %s" % (mark, name, detail))
    print("prerelease: %s" % ("all passed" if failed == 0 else "%d FAILED" % failed))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
