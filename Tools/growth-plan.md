# Managing the addon's growth (2026-11-15)

The seven steps from the review, what was done for each, and what's waiting
for your decision. **Nothing is committed.** All checks pass on the working
tree: luacheck, `Tools/check-toc.py` and the offline check. None of it has been
tested in game.

## Done (uncommitted)

| Step | What changed |
|---|---|
| Map of the addon | `ARCHITECTURE.md`: load order, the tick and the frame pass, building blocks to reuse, areas, the rules every change follows. |
| Automatic checks | `Tools/hooks/pre-commit` (luacheck, TOC check, offline check: about 17 s). It checks only what's being committed, so other sessions' unfinished edits don't block a commit. **Not switched on yet** (see below). `Tools/check-toc.py`: the dev TOC is the release TOC plus dev-only files, in the same order, and every dev-only file is left out of the package. |
| TOC drift fixed | `Cinematic.toc` now loads `ShoulderCalibrate` before `MultiQuestFix`, and `DamageVision`/`DamageReport` after `EmoteVision`, as the dev copy (the tested order) always did. |
| Growth numbers | `Tools/stats.py` (`--save` adds a line to `Tools/stats.csv`; the first line is there). Today: 197,536 code lines, 12,849 functions, 43 over 300 lines, 8 files near the local cap, 184 one-time settings updates, 749 KB saved settings. |
| Dead code | 13 `ns` functions nothing called, removed (69 lines): `IsAtCampfire`, `SetBuiltinCameraRule`, `TriggerTakesScripts`, `InCameraMode` (the `ns.` copy only), `HideDamageReport`, `NameRowHasOwn`, `TargetMarkFits`, `RecapLineFor`, `ShoulderCalibrateRunning`, `StyleToggle`, `TestDeathBanner`, `SetBuiltInSourceOrder`, `WhyWindowRows`. |
| Settings build timing | Options.lua logs `load: settings pages made in N ms` once per login (`/cine log`). That number decides step 3. |
| Review fixes | The client label in `/cine debug guess`; luacheck no longer reads `.claude/worktrees`. |

## Waiting for you

### A. Switch the pre-commit hook on (one command, affects every session)

```bash
git config core.hooksPath Tools/hooks
```

Commit `Tools/hooks/` and `Tools/check-toc.py` first (or in the same commit),
or other sessions' hooks won't find the TOC check. (The hook skips it while
it's missing, so nothing breaks.)

### B. Pruning: what to cut (your call on each)

1. **Functions that look unhooked**, kept for now because they may be a bug
   rather than dead code:
   - `ns.ShowCameraTab` (CameraManager.lua): its comment says the minimap
     button's "Cameras in use" opens it, but nothing calls it.
   - `ns.PreviewTintHour` (Tint.lua): "Quick preview from the minimap menu",
     never called. Was the minimap menu's tint preview lost?
   - `ns.ShakeCamera` (LowHealth.lua): a camera shake nothing starts.
   - `ns.CloseRuleEditor` (GridRows.lua): "closes it as the settings go",
     never called. The rule editor may stay up after the settings close.

   Fix or remove each.
2. **Dev-only files: 31 of them, about 14,000 lines**, almost all one-off
   investigations from the last two weeks. These look finished: PortalScout,
   ScreenEffectScout, TintLayerTest, BarHoverTest, LowManaTest,
   PlateWidthTest, PlateFlickerTest, StyleSixTest, IconCropTest,
   DamageVisionMeterTest, HealthRedTest, SpokenTest, LoreForeverTest,
   MouseTurn. The ones still in use (ShoulderCamTest, DemoHub, ThresholdTest,
   FlickerTest, NamesTest, KeysBarsTest, TurnLagTest...) can stay. Git keeps
   anything deleted.
3. **Parked features still in the code:**
   - the void eye portrait (code and 8 textures under
     `Textures/Themes/Shapes/Portrait*Eye*`)
   - Vitals' parked edge-effect option ("no theme has one now", LowHealth.lua)
   - Minimap Copy (dev page)
   - Wind Guide (dev demo)

   Keep each one only if you'll come back to it soon.
4. **Old one-time settings updates (184).** One that ran more than a month
   ago has done its job for everyone who has logged in since. Removing them
   would shorten the 4,225-line load handler and keep it under Lua's limits.
   The catch: a player coming back after months would miss them. A safe way
   is to keep them but move them into a `Migrations.lua` list of named steps
   (review finding 2).

### C. Feature folders (one command when you say go)

`Tools/reorganize.py` moves 160 files into `Camera/`, `Atmosphere/`,
`Visions/`, `Plates/`, `Style/`, `UI/`, `QoL/`, `Profiles/` and `Dev/`. Core
pieces (Core, Frames, Effects, Options, Diagnostics, Slash, Support/,
Locales/...) stay at the top. It rewrites both TOCs, `.pkgmeta` (all dev-only
files become one `Dev` line) and the four tools that open files by path.
**Tried on a copy: luacheck, the TOC check and the offline check all pass.**

```bash
python -I Tools/reorganize.py
```

That's a dry run. With `--apply` it moves the files. Run it with no other
session working (it refuses while a file it moves has uncommitted changes),
commit right after, then quit and restart the game. A `/reload` doesn't read
a changed TOC.

What it doesn't do: move each feature's defaults out of Core's `DEFAULTS` into
its folder. That's the next step after the move, a feature at a time, when you
touch it anyway.

### D. Loading settings only when opened

What blocks it today:
- **Every page is built at login** (in Options.lua's `ns.OnLanguage` setup),
  and the build is now timed in the log.
- **About 30,000 lines** are settings-only files. Another 34 page builders sit
  inside 28 feature files (the Style pages, LowHealth, ShoulderCam,
  EmoteVision...).
- **43 things the settings files define are used by game code**, most of all:
  - `ns.OpenOptions` and `ns.RefreshOptions` (13 files)
  - `ns.ShowTable` (Show in rows, built for pages by feature files)
  - `ns.letterboxDirty`
  - `ns.FolderTabs` and `ns.lowHealthKit`
  - `ns.PageSettings`: the profiles read the page list to know each module's
    scope
  - `ns.FindSetting`: `/cine find` needs the pages built

Suggested path, smallest risk first:
1. Read the log's `settings pages made in N ms` on both clients. Under about
   100 ms, stop: it isn't worth it.
2. If it's worth it, **make each page's contents on its first open** inside
   the same addon. The page's frame and its menu entry stay at login. That
   gives most of the gain without a second addon. `/cine find` and the
   profiles' page list would then build what they need when asked.
3. Only after that, if memory matters, a separate load-on-demand addon
   (`Cinematic_Options`). Its code would share `ns` through one global, and
   the 43 links above would move to the game side first.

### E. Pacing (no code)

- **Alternate:** a few days of features, then a few days of only fixing,
  cleanup and in-game testing. The Style revamp (six releases, untested in
  game) is the first candidate for a test-only stretch.
- **Fewer sessions at once,** one per area (Camera, Style, Plates...), so they
  don't edit the same files.
- **Run `python -I Tools/stats.py --save` at each release,** and add the
  in-game numbers (settings build ms, `/cine debug cpu` ms per frame in a
  city) to the CSV line by hand.
