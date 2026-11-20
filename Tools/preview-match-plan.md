# Preview Match plan (2026-11-19)

Goal: every Style preview looks like the frame it stands for, on the client the player is on, and a test proves it
before every release.

## Status (2026-11-20): cast bars done, the rest to go

Done and committed (ee3d51f, b86a5bf, 5c584c6, d17755a2, 289d3821; in v2.1.17 up to 5c584c6):
- Step 0 on both clients (`/cine debug templates`, results below).
- The match test, `/cine debug previewmatch` (Dev/PreviewMatch.lua): runs itself, never opens Settings (on Forever
  that prints the gamepad "Interface action failed" line), builds its own preview bars with the pages' code
  (`ns.MakeCastLookSample`), reads your bar, your target's (target yourself) and a nameplate's (it turns nameplates on
  for those steps, out of fights only; your pet's casts count), compares part by part incl. colors, verdicts, screenshots.
  `python Tools/preview-match/build.py [forever|retail]` makes the side-by-side page.
- Cast bar previews built from the game's templates (PlateCastStyle.lua `MakeSample`, SAMPLE_KINDS). Forever scores:
  63/62/53 before, 100/100/100 after (your bar / target / nameplate).
- Your cast bar has its own tab, Unit Frames > Your Cast Bar (`playerCastStyle`), user's pick.
- The "other kind's game look" pick (GameAs/DressAs): our own copy of name and icon, the game's faded (moving the
  game's failed where their place is secret). Offline: Tools/offline/castlook.lua (42 checks, in prerelease).
- Your bar's preview tinted by Interface Recolor's irCast like the real one (`ns.RecolorLike`).

Known gaps on cast bars:
- The can't-be-interrupted shield stays the game's in the other look (not moved with our copied icon).
- The nameplate preview's icon and name are placed by client (retail under the bar, Forever on it); the game decides
  by the player's nameplate style. Plate anchors read in game would settle it.
- Retail: no match test run yet.

Next (the order of work below, step 4): unit frames (copy, B), nameplates, action bars (A), raid (B), tooltip (A),
personal resource, roll window, quest item, combat text. Each: add pairs to the match test first, get a baseline,
then fix.

## What's wrong today

- Every preview is hand-built: `MakeSample` (Style/PlateCastStyle.lua) draws a cast bar from loose textures at a
  made-up 140 px width; `MakeUnitStylePreview` (Style/UnitStyle.lua) places frames by hand-typed coordinates
  (`framed = { 150, -140, 36, 80 }`). They drift from the game: on Forever the target cast bar is a gold bar with the
  spell name on a dark plate *under* it; our preview draws a thin bar with the name on top, icon left, a second bar
  under it.
- Nothing checks them. Style Lab (Tools/style-lab) and ThemeShots/PageShots show our previews, but never next to the
  real frame, so nobody sees the gap until a player does.
- Good part to keep: the samples carry the game's part names (`bar.Icon`, `bar.Spark`, `bar.Text`...) so our style
  code runs on them unchanged. The bug is the base they start from, not the styling.

## The idea: stop recreating, use or copy the game's own frame

Three ways to get a preview, best first. Each preview is moved to the best one that works on its client.

### A. Build it from the game's own template (best)

`CreateFrame(type, nil, ourParent, "<Blizzard template>")` makes a real copy of the game's frame: same art, atlases,
fonts, sizes, layers, offsets. We then feed it fake values (spell name, icon, 0-1 value, health, class color) and
switch off its own scripts (`UnregisterAllEvents`, `SetScript("OnEvent"/"OnUpdate", nil)`) so it never reads a real
unit. Our styling then runs on a frame that *is* the game's, so the preview and the real one can't drift, on either
client, after any game patch.

Candidates (names to confirm in step 0, they differ per client):

| Preview | Game template to try |
|---|---|
| Cast bars (yours, target/focus, boss) | `CastingBarFrameTemplate`, `SmallCastingBarFrameTemplate`, retail `PlayerCastingBarFrameTemplate`/`TargetSpellBarTemplate` |
| Nameplate cast bar | retail `NamePlateCastingBarTemplate`; Forever's plate cast bar template |
| Action bars | `ActionButtonTemplate` (not the secure one) |
| Tooltip | `GameTooltipTemplate` (we already create these) |
| Raid frames | `CompactUnitFrameTemplate` (no unit set, values filled by hand) |
| Roll window | `GroupLootFrameTemplate` / retail loot roll template |
| Unit frames, nameplates | probably too tied to units/secure code: B instead, A only if step 0 shows it's safe |

Rules: never a `Secure*` template, never in combat (`ns.Guard`), every create in `pcall` with a fallback to B, and
the template name per client in one table (`PREVIEW_TEMPLATES`), probed at load like `/cine selftest` does.

### B. Copy the live game frame (when the template can't be used)

A generic copier, `ns.CopyGameFrame(realFrame, parent)`: walks the real frame (TargetFrame, a nameplate, the
PlayerFrame...) and rebuilds each shown region: texture file or atlas, tex coords, vertex color, blend mode, size,
anchors, draw layer and sublevel; font strings' font, size, flags, color, justify, shadow; status bars' fill texture.
It reads the shape only, not the unit's values, so secret values in fights don't matter (and it only runs out of
combat anyway).

The copy's recipe is saved per client (`CinematicDB.frameRecipes[client][frame]`), so a preview can be built even when
the real frame isn't up (no target, no boss), and the offline Style Lab can draw the same recipe instead of its
guessed layout. A recipe holds atlas names and file IDs only, no game art, so nothing of Blizzard's is bundled
(see the no-unlicensed-data rule; A and B both use the game's art at runtime, which is fine).

### C. Hand-built (last resort)

Only where A and B both fail (screen effects, bubbles, Cinematic's own frames like cards and Quest Talk, which have no
game twin). These must still pass the match test where a game twin exists.

## Step 0: find how the game builds them (one evening)

1. Export the game's own UI source, once per client, for reading only (never copied into the repo):
   start Wow.exe with `-console`, then in the console (`` ` `` key) `exportInterfaceFiles code`. It writes
   `BlizzardInterfaceCode/` next to Wow.exe. Do it for `_forever_` and `_retail_`. From it we list the exact template
   names, which ones are secure, and which mixins call protected functions.
2. A dev command `/cine debug templates`: tries each candidate template on the current client in `pcall`, logs made /
   failed / taint warning, its size and named parts. One run per client, "check log".
3. Result: a table per preview of A/B/C per client, added to this file.

### Step 0 results

Forever (1.60.1 build 70959, 2026-11-19, `/cine debug templates`): 209 templates looked at, 120 made, 3 failed
(forbidden frames), nothing blocked. Retail (12.1.5 build 70961, same day, fixed probe): 132 made, 3 failed (the
same forbidden frames), nothing blocked. Every template in the table below makes clean on both, with the same parts
and sizes. The live `TargetFrameSpellBar` and `FocusFrameSpellBar` have exactly `TargetSpellBarTemplate`'s parts on
retail, so a preview made from it is the game's bar. Retail has no `PlayerCastingBarFrameTemplate` under that name;
`CastingBarFrameTemplate` sized like `PlayerCastingBarFrame` covers it there too.

Note: `BossTargetFrameTemplate` (built on the secure `TargetFrameTemplate`) slipped past the skip, because only its
direct parents are checked. It made clean on retail and errored on Forever (no name). It would be a whole real target
frame, but it's a secure unit button: keep unit frames on B unless a later test shows it's safe.

| Preview | Forever + retail | How |
|---|---|---|
| Target/focus cast bar | `TargetSpellBarTemplate` made clean, 150x10, Icon, Spark, Text, TextBorder (the dark plate under the bar), BorderShield | A |
| Your cast bar | `PlayerCastingBarFrameTemplate` is Edit Mode (skip); its base `CastingBarFrameTemplate` made clean, sized like `PlayerCastingBarFrame` (208x11) | A |
| Small cast bar (boss, arena) | `SmallCastingBarFrameTemplate` made clean, 150x20 | A |
| Nameplate cast bar | `NamePlateCastingBarTemplate` made clean (Icon, BorderShield, ImportantCastIndicator...) | A |
| Action buttons | `ActionButtonTemplate` made clean (45x45, the game's atlases) | A |
| Tooltip | `GameTooltipTemplate` made clean | A |
| Roll window | `GroupLootFrameBaseTemplate` made clean, 277x67 | A |
| Unit frames (target, player...) | `TargetFrameTemplate` is secure | B |
| Raid/party frames | `CompactUnitFrameTemplate` is secure | B |

Probe changes after the first run: bases that only exist to be built on (ClassPowerBar, ClassNameplateBar, pet battle)
are skipped, because the game warned about them; made frames get a name (action buttons and compact frames need one);
the limit went from 120 to 250.

## The match test (proves it, stays forever)

### In game: `/cine debug previewmatch [name]` (Dev copy)

One recorder run (in-game testing rules: runs itself, no time limit, CineMode off, steps on screen via
`ns.TestPrompt`, everything logged so "check log" is enough):

- For each preview, a pair entry: the preview maker, a getter for the real frame, and how to make the real one show
  (target yourself, start a cast, `/cine debug` dummy plate...). Steps that need the player ("cast Shadow Bolt now")
  wait on screen till it happens.
- With both up and the preview on "The game's" look (all Style off): place the preview at the real frame's size,
  side by side, `Screenshot()`, log both screen rects.
- Structural compare, no pixels needed: walk both frames and diff region by region (atlas/file, tex coords, color,
  size ratio, anchor side, layer, font, font size, justify). Each mismatch logged as one line:
  `cast/target: Text anchor TOP of bar (game) vs CENTER (ours)`.
- Then the same with a Style theme on, both preview and real frame styled, to check our styling lands the same on both.

### Offline: `Tools/preview-match/build.py`

Reads the log and the screenshots from `_forever_/Screenshots` and `_retail_/Screenshots`, crops each pair by the
logged rects, scales to the same size and writes one HTML page: game | ours | difference heat map, a match score per
preview, the structural mismatch lines under each. That page is how we look at it together.

### Kept as a check

- Each preview gets a score floor; `Tools/prerelease.py` and `/cine prerelease` fail when a preview's structural diff
  grows (a new mismatch line) on either client.
- Style Lab draws from the saved recipes, so offline shots match too.

## "Make sense", not only "look right"

Things the test can't catch, fixed as each preview is moved:

- Real proportions: show the frame at the game's size scaled down evenly, never squashed to a made-up width.
- The client's own layout: Forever previews look like Forever, retail like retail (one-client-fix rule: a change for
  one never moves the other).
- Real situations: a target cast bar sits under a target frame, a plate cast bar under a plate, not floating alone.
  Samples show the states players know (casting, channel, can't interrupt) as the game draws them.
- "The game's" pick shows exactly the untouched game frame, so before/after (Hold to compare) is honest.

## Order of work

1. Step 0 (export + `/cine debug templates`), both clients.
2. Build the match test and the HTML report first, run it on today's previews: a baseline score for each.
3. Cast bars first (the user's screenshot; most visible gap): A on both clients.
4. Then by how often players see them: unit frames (B), nameplates + plate cast (A/B), action bars (A), raid (A),
   tooltip (A), personal resource, roll window, quest item, combat text.
5. After each: rerun the match test on both clients, compare to the baseline, keep the HTML page.
6. Last: hook the scores into prerelease and Style Lab.

Each step is tested in game on Forever and retail before the next one starts.

## Risks

- Templates may run code on create (mixins' OnLoad registering events, touching unit APIs): handled by pcall,
  stripping scripts after create, and the fallback to B. Step 0 shows which ones.
- Taint: only non-secure templates, out of combat; the match test also logs any ADDON_ACTION_BLOCKED during the run.
- Retail nameplates and unit frames are partly forbidden/secret: B reads shapes, not values, and saved recipes cover
  the times the frame can't be read.
- Game patches change frames: A follows them by itself; B recipes are refreshed at login when the real frame is read.
