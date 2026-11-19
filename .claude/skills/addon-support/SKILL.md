---
name: addon-support
description: The user typed /addon-support, or asked to add or extend Cinematic's support for another WoW addon (a player says "doesn't work with X"). Checks the installed copy is the latest release, scans its code (every client's copy) for its frames, the game frames it replaces, fade/hover traps, feature clashes and taint risks, reports a plan with a test per frame, on the user's OK writes the Support file, then proves it in game (addon alone with Cinematic, every row hidden and shown, every frame on screen covered).
argument-hint: "<AddonFolderName> [what the player reported]"
---

Adding or fixing support for another addon. Two phases: **report**, then **build only after the user says OK**. Then an in-game test that proves every frame.

## Phase 1: report

1. **Latest version first.** Support written against an old copy misses what the new one adds, and the in-game test runs on the installed copy, so it has to be the latest:

   ```
   python -I .claude/skills/addon-support/latest_version.py <AddonName>
   ```

   It reads each client's installed version and asks GitHub for the newest release (the toc's links, `KNOWN_REPOS` in the script, or `--github owner/repo`). Exit 0 = up to date. Exit 3 (BEHIND) = **stop and ask the user to update it** with their addon manager, in every client it shows, then run again. Exit 4 (can't tell) = look up the latest version yourself on the pages it prints (Wago, CurseForge, its GitHub: web-fetch or search), and when you find its GitHub repo, add it to `KNOWN_REPOS`. Exit 2 = not installed: ask the user to install it. Never download the addon yourself; the user's addon manager does that.

2. Run, from the repo root, with the addon's folder name (as in Interface/AddOns):

   ```
   python -I .claude/skills/addon-support/scan_addon.py <AddonName>
   ```

   Add `--all` for every hit in a list, `--libs` to include embedded libraries. Section 2 reads every client's copy (a frame only one version makes is marked `only _retail_`), with nested XML names (`$parent`) and template children resolved. The scan is static: frames built at runtime from data, unnamed frames and ones its code makes later still slip through. The in-game test (Phase 3) is the final word on frames.

3. The scan only points at places. Read the addon's code itself (the files and lines it names) before deciding anything. Read the scan carefully, then:
   - **Section 2, frames**: **every** named frame gets a decision, none skipped: each UNHANDLED one is either on screen during play (bars, unit frames, trackers, meters, buttons, popouts: it needs a row or a fade) or a window, settings panel, preview or invisible helper (left alone). Open its file and check: being in a list doesn't make it handled (DaylightUI's buff popout and private debuffs were listed and still missed). Work out the patterns behind built names (`"X" .. i`, `*` where the scan can't read a part) and when each frame gets created (load, first use, combat end). Unnamed frames count too: find the ones that draw on screen (a backing frame, a `.back` field) and reach them by their named owner. Frames whose names don't start with the addon's (Questie's `TrackedQuests`) are listed from a plain search: check them too, and if the addon uses a short prefix of its own, add it to `EXTRA_PREFIXES` in Tools/addon-check.py.
   - **Section 3, game frames**: what it replaces or hides. A replaced frame means its frame should fade with that game frame's row (`ns.FadeWithRows`). **Only the frame that really stands in for the game's goes on that row**: its extras the game frame never had (a waypoint arrow, level splits, a timer, a popout of its own) are frames of their own and get their own `ns.ADDON_FRAMES` row. Test each one: would a player want it up while the game frame it'd follow is faded? If so, it's its own row. (Missed for RestedXP: its arrow rode on the Quest tracker row, so players couldn't keep it up while the guide faded.) A frame it only reskins means following its alpha (`ns.FollowOwnAlpha`) or leaving it alone (`ns.LeaveAlone`). Rows live in `ns.COMBAT_SHOW` (Frames.lua); look up row keys and groups there and copy how the existing Support files map them.
   - **Section 4, traps** are what break our fades and hovers. Read every SetAlpha hook in full: one that turns the mouse off below some alpha means the frame needs `ns.HOVER_BY_RECT`. One that sets alpha back means it fights us: `hookAlpha`/own+hook, or `ns.NO_SECRET_ALPHA` if it does math on the value. Its own visibility settings (mouseover, combat fades) mean it sets alpha itself: follow it rather than fight it. A 1x1 holder hovers by its children (already handled). SetIgnoreParentAlpha parts won't fade with their parent.
   - **Section 5, clashes**: CVars it sets that Cinematic also sets (camera, nameplates, minimap rotation...), and features of its own that do what one of ours does (AFK screen, quest dialogs, tooltip/minimap/chat look, damage meter). Each one is a candidate Addon Conflicts row (`ns.AddConflict` / `ns.AddFeatureYield`).
   - **Section 6, taint**: hooks on game code we also touch, secure frames we'd fade (SetAlpha is fine, Hide/SetParent in combat is not), state drivers that show and hide frames themselves.

4. Read Cinematic's side. Start with the existing `Support/<Addon>.lua` if the scan says there is one: extend it, don't start over. Pick the closest model file: FlareUI / ElvUI / EllesmereUI (whole-UI suites), Bartender4 (bars), Plater (nameplates), Questie (quest tracker and minimap pins), Details (meters), Glass (chat), DialogueUI / Immersion (quest dialogs), LeatrixPlus (assorted tweaks). The helpers are in AddonSupport.lua and Frames.lua:
   - `ns.ADDON_FRAMES` rows (Addons page): key, addon, label, short, about, note, names, patterns, match, hookAlpha. Rule: **one of its frames = one row**, never several frames sharing a row. The rule covers `ns.FadeWithRow(s)` lists too: a name list there is several frames sharing a HUD row, fine only when each one stands in for that game frame (section 3). When extending an existing Support file, check its old `FadeWithRow(s)` lists against this too: files from before 2026-11-12 grouped frames freely, and the 2026-11-12 split only went through `ns.ADDON_FRAMES`.
   - `ns.ADDON_NOTES`: supported, with nothing to list.
   - `ns.WhenAddonLoads(addon, fn)`: setup runs only once it has loaded.
   - `ns.FadeWithRows`, `ns.FollowOwnAlpha`, `ns.LeaveAlone`, `ns.FadeFoundByName`, `ns.AddScanner` + `ns.AddFoundFrame` + `ns.IsFaded` (unnamed or late frames).
   - `ns.HOVER_BY_RECT[name]`, `ns.NO_SECRET_ALPHA[name]`, `ns.AddPortraitFrame`, `ns.AddPowerBarFrame`, `ns.AddPetFrame`.
   - `ns.AddConflict`, `ns.AddFeatureYield` (Addon Conflicts), `ns.AddPlateAlpha` / `ns.AddPlateHidden` (its own nameplates), `ns.ClaimLinkPart` (FrameLinks.lua: chat parts and the like).

5. Report to the user in chat, short and plain:
   - what it is, which clients and version (and that it's the latest)
   - per frame that matters: the row it would get or follow, and why
   - the traps found, each with file:line and the fix
   - the clashes, each with a suggested Conflicts row (or "leave it")
   - risks (taint, secret values, combat)
   - **a test per frame**: a short table, one line per frame or row: what proves it works (hidden by its row and stays hidden, comes back, hover brings it up, its own setting still works...) and how: the generic in-game test (Phase 3) checks hide, stay hidden, come back, mouse while hidden and "every frame on screen covered" by itself; anything else it can't see (a hover trap, its own mouseover or combat fade, a frame that only shows in a dungeon or a vehicle) gets its own step, written as one action + yes/no, or as a recorder (Dev/<X>Test.lua, the one-run rules) when it needs numbers.

   If the player said what broke, lead with that one: cause, then fix. Ask where any new player-facing control goes before adding it. Then **stop and wait for OK**.

## Phase 2: build (after OK)

1. Write or extend `Support/<Addon>.lua` in the style of the other Support files: a top comment saying what the addon is and how we handle it, plain-English comments, our names only. **Never copy the addon's code or data** into ours, only reference its frame names. If the change needs a new helper (as `ns.HOVER_BY_RECT` was), put it in Frames.lua or AddonSupport.lua with a comment, not inside the Support file.
2. A new file goes in **both** Cinematic.toc and CinematicDev.toc, in the Support block (after AddonSupport.lua, near similar addons).
3. A newly supported addon also gets added to the lists in docs/guides/other-addons.html, docs/guides/cinemode.html, docs/guides/frames.html and README.md (alphabetical where the list is). New player-facing text is in American English. No esES/locale edits (they wait for the release).
4. Run `luacheck .` and `python ~/bin/luacompile.py` on the changed Lua files. Remember the 200-local cap in big files, and that a line starting with `(` after an assignment won't load in WoW. Then `python -I Tools/addon-check.py`: every name the Support file uses must be found in the installed addon (a FAIL = a typo or a name it builds some other way: `NOT_CHECKED` in that file), and every named frame it makes must be covered (a MISS = one nobody decided: name it in the Support file, or add it to `Tools/offline/addon-frames/<Support>.txt` with why it needs nothing; create that list for the addon if it has none). Once the support is right, `--update` saves the addon as it is now as the baseline its next updates are compared with.
5. Go on to Phase 3. Don't commit. If a player reported it, draft the reply as one short plain-text block they can paste, once the test has passed.

## Phase 3: test in game

Two dev-copy commands (Dev/AddonTest.lua), so the user only types them. Say which client. Each command in its own code block.

1. **Alone with Cinematic** (recommended: another addon's frames or hooks can't muddy the result): `/cine debug solo <AddonName>` turns every other addon off and reloads. It keeps the addon's own parts (folders starting with its name), what it needs to load, the libraries it can use, and CinematicDev. At each login it shows what's on, and names anything else that still loaded. `/cine debug solo off` puts the user's addon list back and reloads. More than one addon: `/cine debug solo A B` (a clash between two).
2. **The test**: `/cine debug addontest <AddonName>` runs itself, with a lasting on-screen box saying what to do: target anything, fight something (it goes on when the fight ends), then hands off while it hides and shows each row the addon's frames fade with (its Addons page rows and the game rows its frames stand in for), with a screenshot of each hidden row. All along it lists every frame the addon made that draws on screen (told by the game's taint record, so unnamed and runtime frames count too), each covered by us, left alone, or **NOT COVERED**. `quick` skips the target and fight steps. CineMode is off for the run, back as it was after. The DONE box says to /reload and "check log".
3. On "check log": read `CinematicDB.addonTestLog` in `WTF/Account/*/SavedVariables/CinematicDev.lua` of that client (and the screenshots it names, in `Screenshots/`). Every `VERDICT ... FAIL` and every `NOT COVERED` frame is work: a frame NOT COVERED gets a decision like a Section 2 one (a row, a fade with its owner, `ns.LeaveAlone`, or listed in `Tools/offline/addon-frames/<Support>.txt` with why). A "by X from its field" owner only says who touched the frame: check before blaming the addon. A row that "has no frames" was off, its page off, or the frame wasn't made yet. Fix, then the same test again: no guess-fix loops, read the log first.
4. Steps from the per-frame test table the generic test can't do: hand them over after it passes, one action + yes/no each.
5. When it's all green: `/cine debug solo off`, and `python -I Tools/addon-check.py --update` for the baseline.
