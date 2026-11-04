---
name: release
description: The user typed /release. Gather everything uncommitted in C:\dev\Cinematic, run the checks, review it, find missing translations and guidebook updates, and stop for the user's review; on their go-ahead, commit it in player-readable commits, push, tag the next version and push the tag (the GitHub Action uploads to CurseForge).
argument-hint: "[quick] [version, default next patch] [anything to leave out or note]"
disable-model-invocation: true
---

# /release

A release takes **everything uncommitted** in C:\dev\Cinematic (on `main`):
here, other sessions' work is the user's own work and is included, unless the
user's words after /release leave something out. Two phases with a hard stop
between them: nothing is committed, pushed or tagged until the user says go.

**`/release quick`** (the first word is `quick`) skips all of that: see
"Quick release" at the end. Anything else runs the full two phases below.

## Phase 1: gather, check, review (no commits)

1. **Where things stand.**
   - `git branch --show-current` must be `main`; `git fetch origin` and check
     `main` isn't behind `origin/main` (if it is, stop and say so).
   - `git config user.name` / `user.email` must be `sapo` and the noreply
     address, never the real name or Gmail (see the public-identity memory).
   - Latest tag: `git tag --sort=-v:refname | head -1`. Next version = last
     number + 1 (v2.0.7 -> v2.0.8) unless the user gave one.
   - `git status --short`, `git diff --stat`, and the untracked files.

2. **Untracked files.** For each new file decide: part of the release, a dev
   tool, or junk. A new `.lua` must be listed in `Cinematic.toc` and/or
   `CinematicDev.toc` or it never loads. Dev-only ones (only in
   CinematicDev.toc) must be under `ignore:` in `.pkgmeta`; new Tools/Media
   files are already covered by its folder entries. New `Textures/*.tga` need
   only a /reload in game. Anything that looks like scratch output, ask.

3. **Checks**, on every changed or new `.lua`:
   - `"$USERPROFILE/bin/luacheck.exe" .` (baseline is 0 warnings).
   - `python ~/bin/luacompile.py <files...>` (Lua 5.1 load: 200-local cap,
     syntax). luacheck misses these.
   - Lines starting with `(`: check the line before isn't an expression
     statement (WoW's Lua 5.1 "ambiguous syntax").
   - Offline checks, one run per client, stdin from /dev/null:
     `python -I Tools/offline/run.py Tools/offline/check.lua forever Cinematic.toc < /dev/null`
     and the same for `retail`, and for `CinematicDev.toc`.
   Fix nothing yet; failures go in the review.

4. **Review the diff.** Read the whole `git diff` plus the new files, topic by
   topic. Look for real problems: bugs, nil errors, wrong client branches
   (`ns.isRetail` lumps Classic Era in), secret values used in comparisons on
   retail/Forever, raw `SetScript("OnUpdate")` instead of `ns.SetOnUpdate`,
   leftover debug prints, half-finished work, player text in British spelling
   or missing from `Locales/esES.lua`, a dev-only feature that leaked into
   `Cinematic.toc`. Note what each change does for players.

5. **Translations.** `python -I .claude/skills/release/translations.py`
   lists, per language (all nine in `Locales/`, esES included), the new
   `L["..."]` keys each one lacks, and stale keys whose English was reworded
   or removed. It only sees literal `L["..."]`: also look in the diff for
   new or renamed page names (`RegisterSubpage`), and tables run through
   `ns.TranslateFields`. Count what's missing; it's written in phase 2.

6. **Guidebook.** The site in `docs/` (GitHub Pages, updated on every push
   to main) is hand-written from the addon's player text. For each change a
   player would notice, find the page that covers it (`grep -ril` the
   feature's words in `docs/`; the page list is PAGES in
   `docs/assets/site.js`; settings are in `docs/reference/settings.html`,
   commands in `commands.html`, client differences in
   `forever-vs-retail.html`). Note what's now wrong or missing there: a new
   setting, renamed page or option, changed default or level, removed
   feature. A big new feature with no page: propose a new one. Skip
   dev-only work and anything internal. (Patch notes and the Discord post
   build themselves from Changelog.lua and the commits: nothing to do.)

7. **Plan the commits.** Group the changes into topics, one commit each
   (every subject is shown to players on What's new > All changes). Subjects
   in the house style of `git log --oneline -15`: "Area: what changed, for
   players", American English. Dev-only work never in a subject (body only).
   No "Fixes #N" / "Closes #N" anywhere; "(issue #N)" is fine.
   A file whose hunks belong to two topics: say so; it's split at commit time.

8. **Stop and show the user**, briefly:
   - the version it will be (vX.Y.Z),
   - each planned commit: subject + its files,
   - check results (pass, or the exact failure),
   - translations: how many keys missing / stale, per language,
   - guidebook: each page and what it needs (one line each),
   - review findings, worst first, each with file:line and a proposed fix,
   - untracked files you'd leave out, and why.
   Then ask with AskUserQuestion what to do: fix the findings first
   (recommended when there are any), release as is, or stop. They may also
   reword subjects or drop things. **End the turn there.** Never go on to
   phase 2 in the same turn as the review.

## Phase 2: on the user's go-ahead

9. Apply any fixes they agreed to and re-run step 3 on those files.

10. **What's new**: run the whats-new skill over the whole release; any New
    features entry only with the user's yes (it goes in the matching commit).

11. **Translations**: write every missing key into each locale file, in that
    language, under a comment naming the source file (as the files do now);
    for a stale key, move its translation onto the new English key (reworded
    to match) and delete the old line. Keep `%s`/`%d`, `|c...|r` color codes,
    `\n` and command words (/cine ...) as they are. Row labels on the Game
    Frames page stay under ~30 characters. Keys used with `..` or tables:
    check by hand. Re-run the script until it prints nothing missing, then
    luacheck + luacompile the locale files. They go in the matching topic's
    commit (they're shared files: split by topic like any other).

12. **Guidebook**: make the page edits from step 6 in plain player wording,
    American spelling, no file names, dev tools or CI; a new page gets the
    site's head lines and an entry in PAGES. Preview with the `guidebook`
    launch config if layout changed. Docs edits go in the matching topic's
    commit.

13. **Commit** each planned topic in order. `git add <files>` only, never
   `-A` or `commit -a`. For a file split between topics, stage from HEAD plus
   that topic's hunks with context (-U3 patch file + `git apply --cached`),
   never `--unidiff-zero` (see the partial-staging memory). Before each
   commit, check the staged copies:
   `git checkout-index -a --prefix=<scratchpad>/staged/` then luacompile the
   staged `.lua` files, and read `git diff --cached --stat`. Commit messages
   end with the Co-Authored-By line. If something changed in the working tree
   since the review (another session still working), list it and ask whether
   it goes in.

14. **Push and tag**:
    ```
    git push origin main
    git tag -a vX.Y.Z -m "vX.Y.Z"
    git push origin vX.Y.Z
    ```
    The "Package and release" workflow builds it and uploads to CurseForge
    and GitHub releases (`gh` isn't installed). Give the user the link
    https://github.com/sapowowdev/Cinematic/actions to watch it.

15. **Report**: the version, the commits (`git log --oneline <prev tag>..`),
    and what's left uncommitted, if anything. If a commit answers a GitHub
    issue, offer a short draft reply for it and leave the issue open.

## Quick release (`/release quick`)

For a fix that has to go out now. Typing `/release quick` is the go-ahead:
no review, no stop, no questions unless something below blocks it. Skipped
on purpose: diff review, offline checks, translations, guidebook, What's new.

1. `main`, not behind `origin/main` (fetch first), identity `sapo` +
   noreply: same as step 1. Next version = last tag's patch + 1 unless the
   words after `quick` give one.
2. **Only the checks that stop a broken load** (seconds): luacheck and
   `luacompile.py` on every changed or new `.lua`. A failure here stops the
   release: show it, ask whether to fix it now. Never ship a file that won't
   load.
3. Untracked files: include `.lua`/`.tga`/locale/docs files that belong to
   the addon (a new `.lua` must be in a `.toc`); leave out anything that
   looks like scratch (`*.md` notes in the root, logs) and name it in the
   report.
4. **One commit** with everything: `git add <files>` (never `-A`), subject in
   the house style ("Area: what changed, for players", American English,
   dev-only work only in the body, no "Fixes #N"), Co-Authored-By line.
5. Push, tag, push the tag (step 14), then report the version, the commit,
   the Actions link, and what was left out. Mention that translations and
   the guidebook can catch up in the next full `/release`.
