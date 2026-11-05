# Skyriding test plan: what can we read and control?

Before designing a better Skyriding Cam, we need our limits: what the game tells us
while you skyride, and what it lets us change. Everything below is logged to the saved
log by the dev copy's `/cine debug skyride` commands (SkyrideCam.lua). Do a `/reload`
after each run so its log is saved, then tell Claude which runs you did.

## What we know already (flight log, 2026-11-04)

| Question | Answer |
| --- | --- |
| In the air or not | Yes: the gliding info, plain, changes at once |
| Speed | Yes: the gliding info's forward speed (8 at lift-off, 75-84 cruising, surges +10-16) |
| Climbing | Yes, by speed draining fast (83 -> 4 in 4.5 s) with no flat movement |
| Diving | **Not yet**: no dive in the log |
| Height, pitch | **No**: height reads 0, there's no pitch function |
| The game's unit speed | **No**: 0 the whole time you glide |
| Our zoom script | Works: out on take-off, back 2 s after landing |

### Run 1: the game's settings (retail, 2026-11-05)

| Setting | Value (default) | What it likely is |
| --- | --- | --- |
| `AdvFlyingDynamicFOVEnabled` | 1 (1) | The game widens the view with speed while skyriding: may fight our FOV |
| `DisableAdvancedFlyingFullScreenEffects` | 0 (0) | Skyriding's full-screen effects (on) |
| `DisableAdvancedFlyingVelocityVFX` | 0 (0) | Speed lines / wind effects (on) |
| `cameraFov`, `cameraFoVSmoothSpeed` | 90, 0.5 | Field of view, and how fast it eases |
| `advFlyPitchControl` | 3 (3) | How pitch is steered |
| `advFlyPitchControlCameraChase` | 20 (20) | How the camera chases your pitch: the game's own skyriding camera |
| `advFlyKeyboardMin/MaxPitchFactor`, `...TurnFactor` | 2.5/5, 5/8 | Keyboard steering rates: the player's controls, not ours to touch |
| `test_cameraDynamicPitchBaseFovPadFlying` | 0.75 (0.75) | Experimental dynamic pitch (writing test_ ones brings Blizzard's warning) |
| `motionSicknessFocalCircle`, `...LandscapeDarkening` | 0, 0 | Motion sickness aids, off |
| `DriveDynamicFOVEnabled` | 1 (1) | The same speed FOV, for driving (D.R.I.V.E.) |
| Settings: Motion Sickness `PROXY_DRAGONRIDING_SICKNESS` | 4 | Skyriding's motion sickness choice (a Settings dropdown, not a CVar) |

The game's Settings options behind them (by shown name):

| Option | Variable | Value |
| --- | --- | --- |
| Skyriding Screen Effects | `DisableAdvancedFlyingFullScreenEffects` | true (the option shows the CVar's 0 the other way round) |
| Skyriding Speed Effects | `DisableAdvancedFlyingVelocityVFX` | true (likewise) |
| Camera Following Style | `cameraSmoothStyle` | **0: Never** (yours) |
| Camera Shake | `PROXY_SICKNESS_SHAKE` | 2 |
| Keyboard Pitch Camera Follow | `advFlyPitchControlCameraChase` | 20 |
| Camera FOV | `PROXY_CAMERA_FOV` | 90 |

### Run 2: flight shapes (retail, 2026-11-05 10:29)

| Move | What the log shows |
| --- | --- |
| Take-off | Gliding event at once (it fires twice, the first still with the old value); speed 14 and climbing +5/s |
| Level, at cruise | About 55 yd/s, losing only -1.1/s |
| Above cruise (after a surge) | Loses exactly -7/s until back at about 55 |
| Steep climb (25-35 deg) | Speed drains -12/s, down to a floor of 8 |
| **Steep dive (80 deg)** | **Speed rises +17.8/s**, from 10 up to a cap of 55.2, then holds: steep with speed rising (or held at 55.2) is a dive. **Confirmed** |
| Slow or hovering | A flat 8.0 |
| Surge Forward | +17 in one go (from 8: +36) |
| Skyward Ascent | +10 |
| Whirling Surge | +30 |
| Aerial Halt | Down to 8 in half a second |
| Second Wind | No change in speed |
| Landing | Gliding off at once (event and reading) |

- **Every ability shows** as a cast event with its ID: Surge Forward 372608, Skyward
  Ascent 372610, Whirling Surge 361584, Aerial Halt 403092, Second Wind 425782.
- **Steering:** "mouselook" goes true while you steer with the mouse, and facing turned
  up to 170 deg/s.
- **`IsFalling`** is false the whole time you glide: no use.
- **Vigor and charges: not read yet.** The skyriding bar's slots held no spells for us,
  so the log now reads each ability's charges by ID instead, plus vigor from the game's
  vigor widget (4460, which shows up as you take off).
- The game wrote `cameraSavedPitch` (42.35) as you logged out: the log now reads it,
  and `cameraSavedDistance`, on every line to see if they change live.

### Run 3: steering, and vigor read at last (retail, 2026-11-05 10:36)

| What | What the log shows |
| --- | --- |
| Keyboard turning | Facing turns a steady **135 deg/s**; mouselook false |
| Right mouse button, turning | Mouselook **true**, facing up to **270 deg/s** |
| Right mouse button, mouse still | Mouselook true, facing still |
| Left mouse button dragging the view | Mouselook false, facing **still**: the view orbits you, and that can't be read |
| Level flight below cruise (30-40 yd/s) | Loses -1.5/s |

- **Vigor is the charges, and they read fine:** Surge Forward and Skyward Ascent share
  **one pool of 6** (one Surge took both from 6/6 to 5/6). One charge came back in
  **10.4 s** of slow level flight. Second Wind has 3 charges of its own. Whirling Surge
  and Aerial Halt use cooldowns (a cast puts the others on the 1 s global cooldown).
- **The vigor widget (4460) is dead:** it read "3/3, not shown" the whole time,
  left over from Dragonflight. Charges are the source.
- **`cameraSavedPitch` doesn't change live:** 43.4 all flight, 11.4 only when the game
  saved it at logout. So the camera's tilt still can't be read.

So skyriding's effects, camera shake, the keyboard pitch camera follow and the field of
view are all options players set themselves in the game's Settings. Yours has camera
follow off, so the `follow` probe turns it **on** for its 6 seconds.

## What we still need to find out

**Reading the flight**

1. Diving: is it steep with speed rising (no surge)? What does `IsFalling` say?
2. Each skyriding ability as you use it, and the vigor charges going down and back up.
3. Steering: keyboard turns vs holding the right mouse button.
4. The limits: in a fight (secret values?), in instances (no position?), steady
   flight instead of skyriding, Dracthyr Soar, flight paths, landing on water.

**Controlling the camera in the air**

5. Zoom: does the game take our zoom commands mid-flight?
6. Turn and tilt the view: does it turn the view, your flight, or nothing?
7. Field of view: does our setting stick, or does the game's speed effect override it?
8. Camera follow: does it matter in the air?
9. The game's own skyriding camera and motion settings: which exist?

**The screen**

10. Which frames skyriding shows (vigor, its bar), and whether we could fade them,
    in and out of fights.

## Setup (once)

1. `/reload` the dev copy.
2. Turn **Skyriding Cam off** (Camera > Dev > Skyriding Cam) for runs 1-6, so our
   zoom script doesn't mix into the probes. Run 7 turns it back on.
3. Make these macros and put them on keys you can press while flying
   (Escape > Macros, one per macro):

```
/cine debug skyride
```

```
/cine debug skyride probe zoom
```

```
/cine debug skyride probe turn
```

```
/cine debug skyride probe tilt
```

```
/cine debug skyride probe fov
```

```
/cine debug skyride probe follow
```

```
/cine debug skyride frames
```

The first one prints a snapshot and starts the flight log; press it again to stop
(it also stops by itself after 5 minutes).

## Run 1: settings (on the ground, 2 minutes)

These list the game's settings that sound like skyriding, flying, the field of view or
motion effects, with their values:

```
/cine debug cvars fly glid dragon skyrid fov motion vfx velocity
```

```
/cine debug settings flying
```

```
/cine debug settings motion
```

Then `/reload`. **Answers 9.**

## Run 2: flight shapes (3 minutes)

Hold each move for about **4 seconds**, then fly level for 2 seconds before the next.
Steer with the keyboard only (no mouse buttons held).

1. On the ground, mounted: start the log (macro 1). Wait 3 seconds.
2. Take off, fly level.
3. Climb steeply **without** abilities.
4. Dive steeply **without** surging.
5. Level: Surge Forward twice, a few seconds apart.
6. Skyward Ascent once.
7. Whirling Surge once.
8. Aerial Halt, and hover 3 seconds.
9. Second Wind once, if you have it.
10. Glide down gently and land. Stay on the ground 10 seconds (vigor coming back).
11. Take off, touch the ground for a moment, take off again at once.
12. Land, stop the log, `/reload`.

**Answers 1, 2.**

## Run 3: steering (1 minute)

Start the log, then in level flight:

1. 5 seconds turning left with the keyboard.
2. 5 seconds holding the **right** mouse button, turning with the mouse.
3. 5 seconds holding the right mouse button, mouse still.
4. 5 seconds holding the **left** mouse button, dragging the view around you.

Stop the log, `/reload`. **Answers 3.**

## Run 4: camera probes (3 minutes)

Start the log. In level cruising flight, press one probe, **wait 8 seconds**, then the
next. Do turn and tilt twice: once with no mouse button held, once holding the right
mouse button.

| Probe | It tries | Watch for |
| --- | --- | --- |
| zoom | 10 yards out, then back in | Did the camera zoom out and back? |
| turn | Turns the view left for 1 s | Did the view turn, or did you change direction, or nothing? Did it swing back? |
| tilt | Tilts the view up for 1 s | Did the view tilt, or did you climb, or nothing? |
| fov | Field of view 20 narrower for 4 s | Did the view zoom in like a telephoto lens, then back? |
| follow | Camera follow flipped for 6 s (yours is off: it turns it on) | Did the camera start (or stop) swinging behind you while you turned? |

**Write down what you saw for each**: the log records the numbers, but not what the
screen did. Stop the log, `/reload`. **Answers 5-8.**

## Run 5: frames (1 minute)

Press the frames macro three times: mounted on the ground, in the air, and just after
landing. If you can, once more in the air **in a fight** (Run 6a). `/reload`.
**Answers 10.**

## Run 6: limits (as many as you can, log on for each)

- **a. A fight:** start the log, fly over a hostile mob low enough to pull it, keep
  flying a little, land and fight. Press the frames macro mid-fight.
- **b. An instance:** a delve or dungeon that allows skyriding, if you know one:
  a short flight with the log on.
- **c. Steady flight:** use Switch Flight Style, fly a little with the log on, then
  switch back.
- **d. Dracthyr Soar:** if you have a Dracthyr, a Soar with the log on.
- **e. A flight path:** take a short one with the log on.
- **f. Water:** glide down onto water, swim a moment, take off again.

`/reload` after each. **Answers 4.**

## Run 7: our camera (optional, 2 minutes)

Turn Skyriding Cam back on, start the log, and fly through every moment on its page:
take off, Surge Forward, Skyward Ascent, Whirling Surge, Aerial Halt (hover), Second
Wind (tick it first), a steep climb, a steep dive, a hard turn with the **keys**, then
the same turn with the mouse. Then Surge Forward twice quickly and Whirling Surge straight
after: with Blend on, the zoom should carry on smoothly, not stop and start. Scroll the zoom once in the air. Land, take off again
straight away, land for good. `/reload`. Note any move that didn't happen, went the
wrong way (the turn's swing direction is a guess until now), or jerked.

## Afterwards

Claude reads the saved log, fills in the table at the top, and lists what we can and
can't control: that list is what the camera gets planned from.
