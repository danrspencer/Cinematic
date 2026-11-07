# Shoulder Cam plan

The Skyriding Cam got good by measuring first: find what the game does, simulate it, then build. This is the same approach for the Shoulder Cam, so each trip into the game answers as many questions as possible.

The Shoulder Cam stays a held setting, not a camera: it doesn't move the view and doesn't claim the camera lock. It stays dev-only until Phase 6.

## Where it stands

**Built:** on/off switch, offset, side, swap key, Show in row, pause while mounted and for our framing cameras, Frames follow you, DialogueUI hands-off.

**Open bugs and doubts:**

| # | What | Evidence | Fix in |
| --- | --- | --- | --- |
| 1 | The warning comes at every session, /reload included: the game clears the offset, so we must write it again. Stopping its event keeps it away (Run 2b, Forever). | Run 2, 2b | Phase 1: your decision below |
| 2 | "It keeps resetting even when off" wasn't reproduced on Forever in Run 2. Retail, where it was reported, is untested. | Run 2 | `watch` on retail if it comes back |
| 3 | Turned off in a fight, a protected frame stays moved for good: `PutBack` forgets it even if `Place` refused. | Sim: "Off in a fight" | Not on Forever: Run 1 shows neither frame protected out of a fight. Retail and Classic Era still to check |
| 4 | Frames follow you ignores model and mount size. The game scales the offset by them, so frames miss on anything but a standard model. | Sim: "Tall model", community reports | Phase 2 |
| 5 | At normal distance the offset barely shows. If the sum is right, 2 yards at 12 yards away is only 8% of the screen off the middle; a real third would take 4 yards. | Sim page, Try a shot | Phase 3 |
| 6 | Whether any of this exists on Classic Era and retail's frames is unknown. Forever has every setting. | Run 1, Forever | Run 1 |
| 7 | Frames follow you did nothing on Forever with a chained layout (cast bar on the PRD, the PRD on EssentialCooldownViewer). Fixed 2026-11-07: the first of ours in a chain moves, the rest ride along; plates stay. **Tested in a recording (left shoulder, Forever): the cast bar sits right under you at normal distances.** Zoomed right in (~1.5 yd) it went well past your body, to where your head-top is: frames now stop sliding further in than 3 yards | Run 1, recording | Done |
| 8 | ~~The sum assumed `cameraFov` is across your screen.~~ Fixed: it's across a 16:9 screen, the height kept (Run 3). | Run 3 | Done |
| 9 | The cast bar slid over the player frame: in Retail Inspired it sat on the PRD, and with empty Cooldown Manager rows (a low character) the stack sank it into the unit frames' band. Fixed 2026-11-07: the cast bar is 400 units up from the screen's bottom, as the unit frames are placed. **Tested: works** | Screenshot, frames log | Done |

## What we think the game does

From other addon authors and forum posts, none of it official or tested by us yet:

- The real offset is scaled by the size of your model, or of what you ride. It seems to be a share of the model's width.
- Each race and mount differs. Mounting moves you toward the middle; dismounting shifts the camera sideways.
- No event fires when that scale changes, so a correction applied at the wrong moment jerks the camera.
- Your chat bubble sits right over your character, which gives us a way to measure.
- Keep Character Centered blocks most of this (known since patch 9.0.1).
- The other experimental settings are `test_cameraDynamicPitch`, `test_cameraHeadMovementStrength`, `test_cameraTargetFocusEnemyEnable` and `test_cameraTargetFocusInteractEnable`, each with tuning values.

**Licensing:** two addons already correct for this with tables of race and mount sizes. We don't copy those tables: we measure our own.

## The tools

### Test commands (dev copy, ShoulderCamTest.lua)

Everything goes to the saved log under `shoulder:`. A `/reload` saves it.

| Command | What it does |
| --- | --- |
| `/cine debug shoulder` | State: switch, offset, pause reason, frames |
| `/cine debug shoulder scan` | Every camera setting and its default, which ones this client lacks, who you are |
| `/cine debug shoulder frames` | How the cast bar and PRD are anchored, and whether they're protected |
| `/cine debug shoulder watch` | Toggle, stays on over reloads. Logs every camera setting change and **who made it**, the warning popup, mounts and forms, and values at each login and logout |
| `/cine debug shoulder quiet` | Toggle, stays on over reloads; off takes a /reload. Tests keeping the warning away by stopping its event, as DynamicCam does |
| `/cine debug shoulder sweep offsets` | **Measures.** Says a line in /say, steps the offset 0 to 2, -1, -2, and reads your bubble at each step |
| `/cine debug shoulder sweep zoom` | The same at 5, 8, 12, 15, 20 and 28 yards, leaving out any past your max zoom. It puts your zoom back after |
| `/cine debug shoulder sweep ease` | Logs every 0.05 s through a big step: how fast the game eases |
| `/cine debug shoulder sweep next` | A bubble only lasts a few seconds. Says a new line and carries on |
| `/cine debug shoulder sweep stop` | Stops and puts everything back |
| `/cine debug shoulder try pitch` (`head`, `enemy`, `interact`) | Turns one experimental setting on for a look; again turns it off |
| `/cine debug shoulder try off` | Puts all of those back |
| `/cine debug shoulder on`, `off`, `left`, `right`, `offset 1.5`, `strength 120` | Sets it from chat, no page needed |

Sweeps say a real line in /say that people nearby can read, and need you outdoors, out of a fight and out of instances. Each step prints `real/worked-out`: 1.00 means the Frames follow you sum was right.

### The simulator (Tools/shoulder-sim)

```
python Tools/shoulder-sim/build_sim.py <out.html>
```

It plays a session through the real ShoulderCam.lua and ShoulderCamTest.lua: zooming, swapping, mounting, cameras, Edit Mode, a fight, a flight, dying. Each run checks that everything ends where it began. It stops with an error on any new failed check. To test your own saved settings:

```
python -I Tools/offline/run.py Tools/shoulder-sim/sim.lua yours out.json "<SavedVariables>/CinematicDev.lua"
```

**Rule, as with Skyriding:** before asking for a game test, run the sim on the defaults and on `yours`.

Numbers in `GAME` at the top of sim.lua are guesses. Each run below replaces one with a measurement.

## Test runs

Do a `/reload` first after any code change. Runs are grouped so one sitting covers a lot. Paste the first command of a run, do the steps, `/reload`, and say which runs you did.

### Run 1: what's here (each client, 2 minutes)

```
/run SlashCmdList.CINEMATIC("debug shoulder scan") SlashCmdList.CINEMATIC("debug shoulder frames") ReloadUI()
```

Answers: do these settings exist on Forever and Classic Era, are the frames protected, how are they anchored?

### Run 2: the login warning and the mystery writer (5 minutes)

```
/cine debug shoulder watch
```

1. `/cine debug shoulder on`, press Accept.
2. `/reload`. Did the warning come up?
3. Log out to the character screen and back in. Did it come up?
4. Quit the game fully and start it. Did it come up?
5. `/cine debug shoulder off`, play a minute, `/reload`.

Answers: does the value survive a reload, a relog and a restart, and what writes it while it's off?

### Run 2b: can the warning stay away? (3 minutes)

```
/cine debug shoulder quiet
```

First make sure DynamicCam and DialogueUI are off: both hide the warning themselves. Then `/cine debug shoulder watch`, `/cine debug shoulder on`, `/reload`, and check for the warning. Then a full relog. Then turn off `on`, `quiet` and `watch` the same way.

Answers: does stopping the event keep the warning away, is anything broken by it, and does it work on retail?

### Run 3: the real numbers (10 minutes, outdoors, somewhere quiet)

```
/cine debug shoulder sweep offsets
```

Then `sweep next` whenever it asks. Then `sweep zoom`, then `sweep ease`.

Answers: is a negative value really the left shoulder, is the shift straight with the offset, does it fall with distance as the sum says, and how fast does it ease?

### Run 4: sizes (15 minutes)

`sweep offsets` on each of: your main, a small race, a big race, a small mount, a big mount, a flying mount, a druid form if you have one. Keep `watch` on, so mounting and form changes are logged too.

Answers: how much each scales it, whether it's the same at every distance, and the moment the scale changes.

### Run 5: the look (15 minutes, just play)

`/cine debug shoulder on`, then walk, fight, ride, go indoors. With `try head`, `try pitch`, `try enemy` and `try interact`, one at a time.

Answers: where does it feel wrong, which experimental settings are worth keeping?

### Results

| Run | Client | Date | Result |
| --- | --- | --- | --- |
| 1 | Forever | 2026-11-06 | Every camera setting and ResetTestCvars are there. Offset 0, Keep Character Centered 1, max zoom factor 1. Cast bar on PRD, PRD on EssentialCooldownViewer, neither protected, so Frames follow you moves nothing. Screen 1835 x 768 |
| 1 | Retail | | |
| 1 | Classic Era | | |
| Notice | Forever | 2026-11-07 | Built and tested: our notice once, then no warning from Blizzard at the switch or a /reload. "Works" |
| 2b | Forever | 2026-11-07 | **No warning** with `quiet` on: not at the write, the /reload or the relog. Forever hears the event through GameEvent (`GameEvent.UnregisterInternalEvent` is there); UIParent wasn't listening at all, so the old way alone would have done nothing. Once stopped, the event stays stopped until a /reload. CameraReduceUnexpectedMovement was already 0 here, so it wasn't written |
| 2 | Forever | 2026-11-06 | The game clears the offset to 0 at every /reload, relog and restart; Keep Character Centered stays. So we write it each session and the warning comes each time (you saw it 3 of 3). It shows about a second after the write. Turned off, it restored both settings and nothing else wrote them for the 29 seconds logged. The reported "keeps resetting while off" didn't happen here |
| 3 | Forever | 2026-11-07 | Done, second try (the long line's bubble lasted the whole sweep). Dwarf, zoom 9: 0.5, 1, 1.5, 2 yards moved you 4.2%, 8.4%, 12.6%, 16.8% off the middle (shares of half the screen), and -1, -2 the same to the right: **negative is the left shoulder**, and it's a straight line, 1.01 of the fixed sum. Zoom 8, 12, 15: 0.98-1.01. **Zoom 5: only 0.44**, but the reading may have come while the zoom still moved; rerun with closer steps. The game eases over in about 0.3 s. First try: the ultrawide screen (2.39:1) made the old sum 0.74 too big; cameraFov is across a 16:9 screen, the height kept |
| 3b | Forever | 2026-11-07 | **No fade up close**: 1 yard moved you 4.9%, 6.2%, 9.4%, 12.6%, 15.3%, 19.3%, 26.3%, 41.0% at 15, 12, 8, 6, 5, 4, 3, 2 yards: 1.00-1.04 of the sum down to 4 yards, 1.06 at 3, 1.11 at 2 (as if the camera were ~0.17 yd nearer than its zoom reads: not worth a fix). Run 3's 0.44 at 5 yards was read mid-zoom. Up close you're near the top of the screen (bubble y 0.9 at 2 yards) |
| 4 | | | |
| 5 | | | |

## Build phases

Each phase ends with the sim passing, including its new checks, then one game test.

### Phase 1: solid ground (after Runs 1 and 2)

- Settle the login warning: **built 2026-11-07.** Our notice once (Accept or Cancel), then the game's warning kept quiet while it's on. You chose this over one warning per session.
- Step aside when DynamicCam is on.
- Fix the frames left moved after a fight: keep them and put them back when the fight ends.
- Frames follow you on chained layouts: move the first frame in the chain that's ours to move, and let what's anchored to it ride along, never both.
- Correct the file header's claim about logout.
- Solve the "off but still on" report with `watch`.
- Sim: fix the `KNOWN` failures in build_sim.py.

### Phase 2: size correction (after Runs 3 and 4)

- Our own measured factors, by race, and by mount size if a pattern holds.
- A **calibrate** button: say a line, read the bubble, save the factor for what you're on now. This covers every mount without a table.
- Writes the corrected offset, so the look stays the same as you mount and dismount.
- Frames follow you uses the same factor.
- Retire "Not while mounted" as the only answer, or keep it as a choice.
- Sim: real factors in `GAME`; a new check that framing holds through a mount.

### Phase 3: framing that holds (after Run 3)

**Built 2026-11-07:** Spot on screen replaces Offset (you chose replace). Default 20% of the way to the edge, 5-40%. The offset follows your zoom every frame (written when it changes by 0.02 yd or more, up to 15 yd), and eases to the middle closer than 4 yards. Sim check: your spot holds as you zoom. Untested in game.

- **Hold your spot on screen:** you pick a spot, say 20% off the middle, and the offset grows with distance so it stays there as you zoom. Probably the biggest improvement to the look.
- **Ease to the middle up close,** so first person and tight shots don't throw you off.
- Limits for how far the offset can go. The slider stops at 2 today; Try a shot shows why that's too low.
- Sim: a check that your spot holds within 2% through a zoom.

### Phase 4: situations

- Per-situation offsets: in a fight, indoors, swimming, in a group, each with its own value or off. These can ride on the Show in row and CQL rather than new settings.
- Smooth side changes for a swap, if the game's own ease isn't enough.
- Auto side: swap toward open space or toward your target. Needs the look test first.
- Sim: a session for each.

### Phase 5: the rest of the action camera (after Run 5)

Only what passes the look test: head movement, dynamic pitch, target focus. Each one writes a test_ setting, so each is held and restored, an allowed exception to not mirroring game settings. Target focus turns the camera, so check it against the camera lock first.

### Phase 6: joining the rest of Cinematic

- A scene step in camera scripts: set the shoulder for a shot, put it back after.
- Replace the pause with real handovers: quest cam and Chat Cam choose a side based on who you're talking to.
- Frames follow you for more frames, if wanted.
- Release: Cinematic.toc, What's new, docs page, translations at release.

## Decisions for you

- Where new controls go on the page (asked per control as each phase starts).
- Is one warning per login acceptable, if that's what Run 2 shows?
- Is the sweep's line in /say OK, or should it use a party or a private way? A private way may not make a bubble.
- Does the Shoulder Cam go public, and on which clients? That waits on Runs 1 and 2.

## What DynamicCam does (read 2026-11-06, v2.21.6, MIT license)

| Topic | What it does | For us |
| --- | --- | --- |
| The warning | Never shows it: `GameEvent.UnregisterInternalEvent("EXPERIMENTAL_CVAR_CONFIRMATION_NEEDED")`, or `UIParent:UnregisterEvent(...)` before WoW 12.1. DialogueUI does the same | The likely answer to bug 1. `quiet` tests it |
| Blocking settings | Turns off `CameraKeepCharacterCentered` **and** `CameraReduceUnexpectedMovement` (needed since 11.0.2), and prints that it did | We missed the second. Fixed: held and restored like the first |
| Timing | Waits 0.1 s after startup: "the camera doesn't like changing cvars on startup" | We write at PLAYER_ENTERING_WORLD. Delay it if a login looks wrong |
| While zooming | Doesn't write the offset mid-zoom | Check in Run 5 |
| Range | Offset -15 to 15 | Our 2 is far too low: Phase 3 |
| Zoom | The offset can follow a curve you draw against distance, with easing | Same aim as Hold your spot; ours is one spot instead of a curve |
| Situations | Eases the offset per situation, with its own timing | Phase 4 |
| Model and mount size | **Not in DynamicCam.** It's a separate addon, CameraOverShoulder Fix, which DynamicCam calls if present (`cosFix`) | Still ours to measure: Phase 2 |
| Screen frames | Doesn't move them | Frames follow you is ours alone |

If DynamicCam is on, it owns the offset and writes it constantly, so we must step aside. That moves up from Phase 6 to Phase 1.

## Sources

- [CameraOverShoulder Fix](https://github.com/Bitwise1057/CameraOverShoulderFix) and [its CurseForge page](https://www.curseforge.com/wow/addons/cameraovershoulder-fix-dynamiccam)
- [SteadyCam](https://www.curseforge.com/wow/addons/steadycam)
- [Behaviour of test_cameraOverShoulder (forum)](https://eu.forums.blizzard.com/en/wow/t/behaviour-of-test-cameraovershoulder-console-variable/50630)
- [CVar ActionCam (Warcraft Wiki)](https://warcraft.wiki.gg/wiki/CVar_ActionCam)
