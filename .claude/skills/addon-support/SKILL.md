---
name: addon-support
description: The user typed /addon-support, or asked to add or extend Cinematic's support for another WoW addon (a player says "doesn't work with X"). Scans the addon's installed code for its frames, the game frames it replaces, fade/hover traps, feature clashes and taint risks, reports a plan, and on the user's OK writes the Support file.
argument-hint: "<AddonFolderName> [what the player reported]"
---

Adding or fixing support for another addon. Two phases: **report**, then **build only after the user says OK**.

## Phase 1: report

1. Run, from the repo root, with the addon's folder name (as in Interface/AddOns):

   ```
   python -I .claude/skills/addon-support/scan_addon.py <AddonName>
   ```

   Add `--all` for every hit in a list, `--libs` to include embedded libraries. Exit 2 means it isn't installed in any client: **stop and ask the user to install it** (with their addon manager, in the client they play it on), then run again. Never download it yourself.

2. The scan only points at places. Read the addon's code itself (the files and lines it names) before deciding anything. Read the scan carefully, then:
   - **Section 2, frames**: **every** named frame gets a decision, none skipped: each UNHANDLED one is either on screen during play (bars, unit frames, trackers, meters, buttons, popouts: it needs a row or a fade) or a window, settings panel, preview or invisible helper (left alone). Open its file and check: being in a list doesn't make it handled (DaylightUI's buff popout and private debuffs were listed and still missed). Work out the patterns behind built names (`"X" .. i`, `*` where the scan can't read a part) and when each frame gets created (load, first use, combat end). Unnamed frames count too: find the ones that draw on screen (a backing frame, a `.back` field) and reach them by their named owner.
   - **Section 3, game frames**: what it replaces or hides. A replaced frame means its frame should fade with that game frame's row (`ns.FadeWithRows`). A frame it only reskins means following its alpha (`ns.FollowOwnAlpha`) or leaving it alone (`ns.LeaveAlone`). Rows live in `ns.COMBAT_SHOW` (Frames.lua); look up row keys and groups there and copy how the existing Support files map them.
   - **Section 4, traps** are what break our fades and hovers. Read every SetAlpha hook in full: one that turns the mouse off below some alpha means the frame needs `ns.HOVER_BY_RECT`. One that sets alpha back means it fights us: `hookAlpha`/own+hook, or `ns.NO_SECRET_ALPHA` if it does math on the value. Its own visibility settings (mouseover, combat fades) mean it sets alpha itself: follow it rather than fight it. A 1x1 holder hovers by its children (already handled). SetIgnoreParentAlpha parts won't fade with their parent.
   - **Section 5, clashes**: CVars it sets that Cinematic also sets (camera, nameplates, minimap rotation...), and features of its own that do what one of ours does (AFK screen, quest dialogs, tooltip/minimap/chat look, damage meter). Each one is a candidate Addon Conflicts row (`ns.AddConflict` / `ns.AddFeatureYield`).
   - **Section 6, taint**: hooks on game code we also touch, secure frames we'd fade (SetAlpha is fine, Hide/SetParent in combat is not), state drivers that show and hide frames themselves.

3. Read Cinematic's side. Start with the existing `Support/<Addon>.lua` if the scan says there is one: extend it, don't start over. Pick the closest model file: FlareUI / ElvUI / EllesmereUI (whole-UI suites), Bartender4 (bars), Plater (nameplates), Questie (quest tracker and minimap pins), Details (meters), Glass (chat), DialogueUI / Immersion (quest dialogs), LeatrixPlus (assorted tweaks). The helpers are in AddonSupport.lua and Frames.lua:
   - `ns.ADDON_FRAMES` rows (Advanced Frames page): key, addon, label, short, about, note, names, patterns, match, hookAlpha. Rule: **one of its frames = one row**, never several frames sharing a row.
   - `ns.ADDON_NOTES`: supported, with nothing to list.
   - `ns.WhenAddonLoads(addon, fn)`: setup runs only once it has loaded.
   - `ns.FadeWithRows`, `ns.FollowOwnAlpha`, `ns.LeaveAlone`, `ns.FadeFoundByName`, `ns.AddScanner` + `ns.AddFoundFrame` + `ns.IsFaded` (unnamed or late frames).
   - `ns.HOVER_BY_RECT[name]`, `ns.NO_SECRET_ALPHA[name]`, `ns.AddPortraitFrame`, `ns.AddPowerBarFrame`, `ns.AddPetFrame`.
   - `ns.AddConflict`, `ns.AddFeatureYield` (Addon Conflicts), `ns.AddPlateAlpha` / `ns.AddPlateHidden` (its own nameplates), `ns.ClaimLinkPart` (FrameLinks.lua: chat parts and the like).

4. Report to the user in chat, short and plain:
   - what it is, which clients and version
   - per frame that matters: the row it would get or follow, and why
   - the traps found, each with file:line and the fix
   - the clashes, each with a suggested Conflicts row (or "leave it")
   - risks (taint, secret values, combat)
   - anything to check in game, because static reading can't tell (frames made at runtime, which client it really runs on)

   If the player said what broke, lead with that one: cause, then fix. Ask where any new player-facing control goes before adding it. Then **stop and wait for OK**.

## Phase 2: build (after OK)

1. Write or extend `Support/<Addon>.lua` in the style of the other Support files: a top comment saying what the addon is and how we handle it, plain-English comments, our names only. **Never copy the addon's code or data** into ours, only reference its frame names. If the change needs a new helper (as `ns.HOVER_BY_RECT` was), put it in Frames.lua or AddonSupport.lua with a comment, not inside the Support file.
2. A new file goes in **both** Cinematic.toc and CinematicDev.toc, in the Support block (after AddonSupport.lua, near similar addons).
3. A newly supported addon also gets added to the lists in docs/guides/other-addons.html, docs/guides/cinemode.html, docs/guides/frames.html and README.md (alphabetical where the list is). New player-facing text is in American English. No esES/locale edits (they wait for the release).
4. Run `luacheck .` and `python ~/bin/luacompile.py` on the changed Lua files. Remember the 200-local cap in big files, and that a line starting with `(` after an assignment won't load in WoW. Then `python -I Tools/addon-check.py`: every name the Support file uses must be found in the installed addon (a FAIL = a typo or a name it builds some other way: `NOT_CHECKED` in that file), and every named frame it makes must be covered (a MISS = one nobody decided: name it in the Support file, or add it to `Tools/offline/addon-frames/<Support>.txt` with why it needs nothing; create that list for the addon if it has none). Once the support is right, `--update` saves the addon as it is now as the baseline its next updates are compared with.
5. Give the user a test: one action and a yes/no answer per step (or a one-run recorder command if what's being proven needs numbers). Say which client.
6. Don't commit. If a player reported it, draft the reply as one short plain-text block they can paste.
