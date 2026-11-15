# Cinematic: whole-addon review (2026-11-15)

Scope: every Lua file the two TOCs load (about 242,000 lines in 237 files,
locales included), the TOCs, `.luacheckrc`, the CI workflows and the saved
settings on this PC. Checked with scripts (pattern counts, function lengths,
main-chunk locals, saved-settings size) plus reading the hot spots. The API and
taint checks are against Blizzard's known API changes, not a line-by-line read
of Blizzard's UI source. No code was changed.

## What's already good practice

- **No stray globals.** `.luacheckrc` lists every global the addon writes and
  reads, and `luacheck` is clean. The only `_G[...]` writes are key-binding
  names, which is the normal way to name bindings.
- **Old and new API both handled.** About 40 calls to functions retail removed
  (`GetSpellInfo`, `GetMouseFocus`, `UnitBuff`, `UnitAura`, `IsAddOnLoaded`)
  were checked. Every one is behind a check for the new API, or for the old
  function existing.
- **Taint-safe habits.** Game functions are hooked with `hooksecurefunc` and
  never replaced. Frames are faded with `SetAlpha` instead of `Hide`/`Show` on
  protected frames. Per-frame state lives mostly in side tables (119 weak
  tables) instead of on Blizzard's frames.
- **Update loops that switch off.** `ns.FeatureLoop` drops a feature's
  OnUpdate when it isn't needed. `ns.SetOnUpdate` stops a loop that keeps
  erroring instead of spamming errors every frame.
- **Measuring instead of guessing.** There's a built-in profiler, a framepass
  timer, an offline check harness (`Tools/offline/check.lua`) and a selftest.
  Few addons have this much tooling.
- **Modern settings panel.** It registers with `Settings.RegisterCanvasLayoutCategory`
  and falls back for older clients, plus the addon compartment and the
  minimap button.

## Findings, most important first

### 1. Bug: the client label in `/cine debug guess` is wrong
`FrameGuess.lua:499` reads
`ns.isRetail and (ns.isClassicEra and "Classic Era" or "retail/Forever") or "classic"`.
`ns.isClassicEra` is only ever true when `ns.isRetail` is false
(`Core.lua:16`), so "Classic Era" can never be printed. Forever isn't
mainline, so it's logged as "classic" too. This only affects a debug log line,
but it can mislead a bug hunt. Fix: test `ns.isClassicEra` first, then
`ns.isRetail`, and add Forever by build number.

### 2. Risk: the load handler is one 4,225-line function
`Core.lua:4781` (the ADDON_LOADED/PLAYER_LOGIN handler) is one closure holding
184 one-time migrations (`...V1 = true` flags) and all the login setup.
Lua 5.1 caps a function at 200 locals and 60 upvalues. Every new migration
brings it closer, and when it goes over, **the whole addon fails to load**.
This trap has already been hit once (see the Lua pitfalls notes). It's also
hard to tell which migration did what to a player's settings.
Suggestion: a `Migrations.lua` with an ordered list of named steps
(`{ id = "cineModeWordGoneV1", run = function(db) ... end }`), each run under
`ns.Guard`, so one failing migration can't stop the rest of loading.

### 3. Risk: several files are near Lua's 200-local limit
Rough count of main-chunk locals (a script, so give or take a few):
Frames 221 (some of those are inside `do` blocks), Effects 203,
PlateParts 197, CameraScripts 194, QuestTalk 191, Camera 188, Options 181,
EmoteVision 179. luacheck doesn't catch going over. The offline check does,
but it only runs at `/release`, so a dev session can break loading without
anyone noticing until then.
Suggestion: a small script that counts real active locals with the parser,
run with luacheck. Over time, move groups of locals into `do ... end` blocks or
into tables like `local Plate = {}`.

### 4. Upkeep: very long functions
43 functions are over 300 lines. The biggest: `CreateTargetArrowPanel`
(Options.lua, 2,066 lines), `HandleSlash` (Slash.lua, 1,903),
`ns.StyleRows` (1,543), `ns.CreateTintStylePanel` (1,247), `CreateVisionPanel`
(1,190), `ns.UpdateFrames` (720, and it runs every pass). These are where
changes land in the wrong spot and where the local/upvalue limits bite.
Suggestion: no big rewrite. When a page is touched anyway, split it into one
function per section. `HandleSlash` would be easier as a table of
`command -> function`.

### 5. Upkeep: the same small helpers copied many times
- The "what's under the mouse" helper (`GetMouseFoci()[1]`, falling back to
  `GetMouseFocus()`) is written out in about 12 files.
- The "spell name by id" helper (`C_Spell.GetSpellName`, falling back to
  `GetSpellInfo`) is in about 10.
- The same goes for aura scanning with the `C_UnitAuras` / `UnitBuff` fallback.

When Blizzard changes one of these again, every copy has to be found.
Suggestion: `ns.MouseFocus()`, `ns.SpellName(id)` and `ns.PlayerBuffs()`,
defined once in Core.lua.

### 6. Design trade-off: every default is written into saved settings
`Core.lua:8687` copies every default into `CinematicDB`. Your dev copy's
account file has **8,999 top-level keys (743 KB)**. The release copy's is
293 KB. The usual practice (AceDB, for example) is to save only what the player
changed and read the defaults as a fallback. Copying them in has two costs:
- Logging in and out reads and writes all of it.
- A changed default never reaches existing players, which is why migrations
  keep piling up (finding 2).

This is tied to how profiles and "Reset" work ("default means reset"), so
it's not a quick fix and might not be worth changing. If you ever rework
profiles, this is the moment to change it.

### 7. Small: the two TOCs have drifted in load order
`Cinematic.toc` loads `ShoulderCam, MultiQuestFix, ShoulderCalibrate`.
`CinematicDev.toc` loads `ShoulderCam, ShoulderCalibrate, ShoulderCamTest,
MultiQuestFix`. DamageVision/DamageReport also sit in different places. So
players run a load order you never run. That's harmless today, but it can hide
a file that uses another file's `ns.X` before it exists.
Suggestion: have `/release` (or check.lua) check that the dev TOC is the
release TOC plus the dev-only files, in the same order.

### 8. Small: luacheck also checks old session worktrees
`.luacheckrc` excludes only `Release/`, so `luacheck .` reads
`.claude/worktrees/*` too: 1,010 files instead of about 250. That's slower,
and stale worktrees could show warnings that aren't in main. Fix: add
`".claude/"` to `exclude_files`. (Seven worktrees are still on disk; the oldest
is from 2026-10-14.)

### 9. To check: closures inside `pcall` in per-frame code
There are about 2,100 `pcall`s. That's expected: secret values on Forever and
retail error when compared, so they have to be wrapped. But
`pcall(function() ... end)` builds a new function every time it runs. In code
that runs every frame (Frames.lua, PlateParts.lua, PlateCastStyle.lua) that's
memory churn and extra garbage collection. Worth one profiler run that looks at
memory per pass (framepass already logs `kb0`). Where it shows, use
`pcall(fn, arg)` with a function built once.

### 10. To check: a few fields written onto nameplate frames
`PlateParts.lua:1433-1711` sets `frame.cineHidden`, `frame.cineMoved`,
`frame.cinePoint` and `frame.cinePlateAlpha` on plate children. On retail,
writing fields onto Blizzard's nameplate frames is a known source of taint.
The rest of the addon already uses weak side tables for this. Moving these
four fields into one would match it. Untested in game: there's no known bug
from it.

## Where the community and Blizzard docs fit in

- **Blizzard's UI source** (github.com/Gethe/wow-ui-source, one branch per
  client including `forever`): the real reference. Checking it before guessing
  an API's behavior would have saved some in-game test rounds.
- **In-game `/api`** (Blizzard_APIDocumentation): argument lists and events for
  the current client.
- **Warcraft Wiki** (warcraft.wiki.gg): per-API pages and patch-change lists,
  useful each time a client patches.
- **WoWUIDev Discord**: where authors of big addons and sometimes Blizzard UI
  developers discuss taint, secret values and new APIs.

## Suggested order

1. Quick fixes: #1 (label) and #8 (luacheck exclude).
2. Guards against breaking loading: #3 (local-count check) and #7 (TOC check).
3. When touching those areas: #5 (shared helpers), then #2 (Migrations.lua).
4. Profile first, then decide: #9 and #10.
5. Leave for a profiles rework: #6 and the long functions in #4.
