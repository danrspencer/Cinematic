# How Cinematic is put together

A one-page map for anyone (or any session) about to change the addon. It says
where things live and which rules every part follows. Each file's own header
comment has the details. Not packaged for players (`.pkgmeta`).

## Load order

Both TOCs load the same files in the same order. The dev copy
(`CinematicDev.toc`) adds its test and dev-only files on top, and
`Tools/check-toc.py` checks that.

1. **Before Core:** `FrameGuess`, `Locales/` (`ns.L["English text"]`),
   `Diagnostics` (log, error net, protected loops), `Profiler`
   (`ns.Profiled`), `Graphics`.
2. **`Core.lua`:** client flags (`ns.isRetail`, `ns.isClassicEra`),
   `DEFAULTS` (most of them), CineMode itself and the main tick, then the
   ADDON_LOADED/PLAYER_LOGIN handler (settings updates via
   `ns.RunMigrations`, defaults filled in, profiles, slash command).
   `Migrations.lua` right after it holds the once-only settings updates, in
   steps.
3. **Features**, roughly by area (below). Each one builds its frames at load
   and hooks into the tick, events or signals.
4. **Last:** `Options.lua` and the page files (the settings window), then
   `Changelog`/`WhatsNew`, `MinimapButton`, `Reload`.

A file can only use another file's `ns.X` at load time if that file is
earlier in the TOC. Inside functions that run later, any `ns.X` works.

## What runs while you play

- **The tick** (`Core.lua`, its OnUpdate): works out whether CineMode should be
  on (`ShouldBeCinematic`), runs the letterbox, tint and effects, and decides
  whether a **frame pass** is due.
- **The frame pass** (`Frames.lua`, `ns.UpdateFrames`): for every faded frame
  (`ns.managed`), its row's Show in rules are asked (`ns.RuleShows`), and it
  fades to the answer with `SetAlpha`. It runs only when something it
  depends on changes (`ns.framesWake`, the mouse, a fight) or on a timer, and
  `ns.UpdateFadingFrames` runs alone while frames are only still fading.
- **The camera director** (`Director.lua`, `ns.DecideScene`): about 10 times a
  second, picks the scene (standing still, travel, an event, death...).
  `Camera.lua` and the camera files run it, and every zoom goes through
  `ns.CameraCall` (`ZoomGuard.lua` watches it).
- **Feature loops** (`ns.FeatureLoop`, Diagnostics.lua): a feature's own
  OnUpdate, there only while `wanted()` says so.

## Building blocks to reuse

| Need | Use | Where |
|---|---|---|
| An OnUpdate | `ns.SetOnUpdate`, `ns.HookOnUpdate`, `ns.FeatureLoop` | Diagnostics.lua |
| A setup step that mustn't stop the rest | `ns.Guard(fn, ...)` | Diagnostics.lua |
| Timing a busy function | `ns.Profiled(name, fn)` | Profiler.lua |
| Another addon's setup | `ns.WhenAddonLoads(addon, fn)` in `Support/<Addon>.lua` | AddonSupport.lua |
| "Something happened" between files | `ns.Listen(name, fn)`, `ns.Signal(name, ...)` | Core.lua |
| A setting, page switch included | `ns.Setting(key)`, `ns.PageSetting(key)` | Core.lua |
| A Show in row (Always, fights, places) | `ns.ShowTable` and the CQL rules (`ns.RuleShows`) | Options.lua, Frames.lua, GridRows.lua |
| Opening a settings page | `ns.OpenOptions(page)` and `/cine find <id>` | Options.lua |
| Text the player reads | `ns.L["English text"]` (American spelling) | Locales/ |
| Why a frame is up | `/cine why`; a new reason needs a line in Explain | Why.lua |

## Areas

- **UI fading:** Frames, HideUI, GridRows, FrameLinks, Chat, Bubbles, Speech,
  Tracking, NodeSweep, CursorHide, PersonalResources, Why/WhyPanel.
- **Other addons:** AddonSupport, Conflicts, `Support/*` (one file per
  addon, one row per frame).
- **Camera:** Camera, Director, ZoomGuard, QuestCam, ShoulderCam (and
  Calibrate, MultiQuestFix), SkyrideCam, ChatCam, CameraRows, Triggers,
  TriggerLibrary, CustomTriggers, Shots, CameraScripts, CameraTests,
  CameraWheel, and their pages.
- **Atmosphere and effects:** Effects (letterbox, names, music, plates and
  CVars in CineMode), Tint, Focus, ScreenEffects, LowHealth, VitalsSound,
  TeleportVision.
- **Visions and cards:** Cards, CombatVision, CardMoments, ZoneCard, Recap,
  EmoteVision, RollWindow, QuestTalk, TalkingHeads, QuestMobs, QuestGlow,
  QuestItemButton, HealVisionFrames, DamageVision.
- **Nameplates:** PlateParts, PlateIcons, PlateGuild, NameRowLook,
  PlateRowLook, PlateThemes, NameThemes.
- **Style hub:** StylePages (shared rows), StyleThemes, GeneralStyle, then one
  file per page (`*Style.lua`), InterfaceRecolor, StyleOverrides.
- **Quality of life:** Campfire, Hunter, HunterAmmo, DragEquip, TalentLink,
  TalentCalc, CenterPanels, XpLeft, KeyboardMap, Reload, the wheels.
- **Profiles:** ProfileChoices (what players pick), ProfileModules (the
  settings behind each pick), Profiles, Share, Backups, Welcome, ShowMe,
  Layouts.
- **Help and tooling:** Slash, SlashComplete, SelfTest, ProfilerPage,
  GameSettingsPage, Changelog, WhatsNew, ThemeShots, PageShots.

## Rules every change follows

- **Only `SetAlpha` on Blizzard frames, never `Show`/`Hide`/`SetPoint` on
  protected ones, and no field writes on them.** State goes in a side table
  with weak keys. Hook with `hooksecurefunc`, never replace a game function.
- **Feature-test, don't version-test.** Check that an API or frame exists
  (`C_Spell and C_Spell.GetSpellName or ...`). `ns.isRetail` only for
  differences by design. A fix for one client must not change the other.
- **Secret values** (Forever and retail, in fights): don't compare, do
  arithmetic on, or concatenate a value that may be secret. Use
  `issecretvalue` or `pcall` it.
- **Lua 5.1 limits:** 200 locals per function (the file's main chunk counts),
  60 upvalues per closure. Big files are near the cap: put new helpers on a
  table or inside a `do ... end` block. The offline check catches going over.
- **Settings:** a new setting goes in `DEFAULTS`, its page's Reset uses it,
  and a page switched off turns off everything on it. Changing an existing
  default for players already playing needs a once-only update at the end of
  `Migrations.lua`, with a `...V1` flag. Check it with
  `Tools/offline/migrate-test.lua`: it runs every update on a real saved
  settings file, with each flag off, so two versions can be compared.
- **Before committing:** `luacheck .` and the offline check
  (`python -I Tools/offline/run.py Tools/offline/check.lua`). The pre-commit
  hook runs both (`Tools/hooks/`, see below). Then the whats-new skill.

## Checks and numbers

- `Tools/hooks/pre-commit`: luacheck, the TOC check and the offline check, on
  every commit. Turn it on once per clone with
  `git config core.hooksPath Tools/hooks`.
- `Tools/check-toc.py`: the dev TOC matches the release TOC.
- `Tools/stats.py`: lines, files, the longest functions, files near the local
  cap and the saved-settings size, with a line added to `Tools/stats.csv` so
  growth shows over time (`--save`).
