# Camera simulator

Plays made-up moments through the addon's real camera code, outside the game, and checks each for what a player
would call a camera bug. Run it after any change to Camera.lua, CameraScripts.lua, QuestCam.lua, ChatCam.lua,
Director.lua or the camera lock in Core.lua.

```bash
python -I Tools/offline/run.py Tools/camera-sim/sim.lua forever all
```

```bash
python -I Tools/offline/run.py Tools/camera-sim/sim.lua retail all
```

```bash
python -I Tools/offline/run.py Tools/camera-sim/sim.lua forever fuzz 1 60
```

- `all`: every scenario in sim.lua (a Hearthstone cast, /sit, AFK, a flight, dying, RP walk, fishing, a quest giver,
  each with your mouse, the gamepad, a fight, a window, a loading screen or a lost mouse release thrown in).
- part of a scenario's name runs just those; `-v:<name>` prints that scenario's log lines too.
- `fuzz <first seed> <count>`: random moments one after another (60 actions each), checked the same way.
  `"fuzz 17"` as the scenario replays one seed.

## What it checks

After each scenario everything is let go, you walk a step, and 40 seconds pass. Then:

- your turn, tilt and zoom speed settings are back to yours
- the camera isn't still turning, no zoom is still under way, no script is playing, the camera lock is free
- the zoom is back where it started (scenarios where you scroll are exempt)
- ours never turned the view while you held the camera (mouse button or the gamepad's right stick) for over 0.45 s (a press under 0.4 s is a click, not a drag, in scenes your input ends)
- no whip: a turn over 100 deg/s, a tilt over 60, a zoom over 12 yards/s with no scroll of yours
  (the Tele camera's own way back is exempt: half a second by design)
- scenes didn't start over and over
- no Lua error in a camera file, no update loop turned off

Scenarios add their own: the scene started, how long after its trigger, it didn't end early, it didn't start again.

## Files

- `world.lua`: the stand-in game. Clock, timers, settings, a camera moved only by the commands sent (as
  Tools/skyride-sim's), a player (moving, fight, AFK, flight, casts, mouse buttons, gamepad, quest giver), and
  `W.Press`, `W.Let(button, lost)`, `W.Cast`, `W.Quest`... that call what the game would.
- `sim.lua`: the scenarios, the checks, the fuzzer.

## What it can't see

The game's own camera (collision, smoothing, what the game does with a turn mid-flight), secret values, real quest
giver positions, other addons. A pass here means the logic holds; it doesn't replace a look in game.
