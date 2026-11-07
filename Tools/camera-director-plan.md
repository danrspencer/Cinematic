# Camera director: plan (step 1)

Agreed 2026-11-07. Goal: nothing camera-related runs every frame unless a
camera is actually moving the view. One place decides which scene is on.

## Why

Profile 15:31 (city, normal UI, no camera running): the orbit camera cost
0.256 ms a frame, the biggest single item. `ns.UpdateOrbit` (Camera.lua:3702)
runs every frame for everyone and does three different jobs in one pass:

| Job | What | Needs every frame? |
|---|---|---|
| A. Bookkeeping | standing-still timer (`ns.stillSince`), last fight, emote ended by moving or turning (`ns.sitFacing`), `ns.manualCam` ended by moving, `NoteTravel`, `UpdateStoppedCam`, `walkHandoff`, `WeaponCozy` | No: edges and timers, 10 a second is plenty |
| B. Decision | `ActiveEvent` → `CurrentEvent` → `ns.PickTrigger` (vista, fish, cozy, tele, AFK), idle, death, travel, flight → `ns.activeCam`, `prefix`, `want` | No: changes on events and timers |
| C. Motion | sway/turn (`ns.orbit`), `UpdateTurnFollow`, `UpdateMouseSteer`, `UpdateIdleZoom`, death tilt, fly-by, spin return, input pause | Yes, but only while a camera moves the view or is easing out |

`ActiveEvent` is cached for one frame only (`cache.at == now`), so B is worked
out afresh every frame and asked again by `IsVista/IsFish/IsCozy/IsTele/
IsEventAFK` and from about 50 call sites (38 in Camera.lua).

## Design

- **The director** (new file `Director.lua`, after Camera.lua in both TOCs):
  a frame that runs A + B about 10 times a second (`DIRECTOR_TICK = 0.1`), and
  at once when woken (`ns.WakeDirector(why)`). It publishes:
  - `ns.scene = { cam, prefix, want, key, since }` (`cam` = what
    `ns.activeCam` is today; `key` = the trigger, as `ActiveEvent` gives it)
  - `ns.Signal("SceneChanged", old, new)` when `cam` or `key` changes.
- **Wake events** (each calls `ns.WakeDirector`): moving starts/stops (the
  hooks that set `ns.playerMoving`), `PLAYER_REGEN_DISABLED/ENABLED`, player
  spell cast start/stop/channel, `PLAYER_FLAGS_CHANGED` (AFK), an emote seen
  (`ns.lastEmote` set), `PLAYER_CAMPING`/`LOGOUT_CANCEL`, taxi start/end
  (`PLAYER_CONTROL_LOST/GAINED`), `PLAYER_DEAD`/`PLAYER_ALIVE`/`PLAYER_UNGHOST`,
  player `UNIT_AURA` (campfire buff), a window opening or closing (whatever
  feeds `WindowPausesCams`), `ns.manualCam` set, `ns.StopCamera`,
  `ns.CameraRowsChanged` (settings), CineMode on/off.
- **`ns.ActiveEvent`** returns the director's last answer. A wake works it
  out again synchronously, so a caller inside an event handler still gets a
  fresh answer. Today's per-frame cache rules (still/emote/manual/moving/
  campfire changed → recompute) stay as a safety net.
- **The orbit** keeps only C, and its `OnUpdate` is attached only while one
  of these is true: `ns.scene.want`, `ns.orbit.level > 0`, a spin return or
  AFK return due, a fly-by running, the death camera dead or busy, idle zoom
  not back to yours, a travel turn-follow gliding. When none is, the
  director detaches it (`ns.orbitFrame:SetScript("OnUpdate", nil)`) and
  attaches it again the moment the scene wants it. (Core.lua:3363, 3386 and
  7110 already attach and detach it on enable/disable: those go through the
  same helper.)

Start latency: event-driven starts (emote, cast, AFK, taxi, death, window)
are immediate. Timer starts (standing still N seconds, travel delays) can be
up to 0.1 s later than today. Nothing moves the view any differently once
it's running: C is untouched.

## Status (2026-11-07)

Phases 1-4 built, offline checks + sims pass, not yet tested in game or
committed. Changed from the plan below: no shadow mode. The director ticks
every 0.1 s whatever happens, so it can't lag more than that and a "differs
for 0.2 s" log could never fire. Instead `/cine debug director` counts (and
the log notes, `director:` lines) each scene change only a tick saw, which is
what a missing wake looks like; it also says whether the orbit is asleep.

## Phases

Each phase is its own commit, offline checks + luacheck + one in-game look.

1. **Extract B (no behavior change).** Move the decision half of
   `UpdateOrbit` (lines ~3703-3840) into `ns.DecideScene(now, cinematic)`
   returning the scene table; `UpdateOrbit` calls it every frame and reads
   the table. Also relieves `UpdateOrbit`'s upvalue pressure (its comments
   note it's close to Lua's limit). Watch the 200-local cap in Camera.lua
   (put new locals in `do ... end`).
2. **Director + shadow mode.** `Director.lua` ticks `DecideScene` at 10 a
   second plus wakes. `UpdateOrbit` reads `ns.scene`. Dev copy only:
   `/cine debug director` also runs `DecideScene` every frame and logs each
   frame where the per-frame answer differs from the director's for longer
   than 0.2 s ("director mismatch: ..."). That finds a missing wake event
   without guessing.
3. **Orbit sleep.** The attach/detach rule above. `/cine debug director`
   prints the orbit's state (running / why awake / asleep).
4. **`ActiveEvent` and `Is*` read the director.** The 50 call sites stay as
   they are; only the function behind them changes.

Then profile: the same city spot (normal UI) and CineMode auto-running in
the open world, compared in ms a second with 15:31.

## Tests

- Offline (`Tools/offline/check.lua`): `ns.PickTrigger` tests already exist.
  Add: a scripted run of states (standing still past the delay, an emote,
  moving, AFK, a window, death, taxi) through `DecideScene` gives the same
  `cam` per step as today's per-frame path; and the orbit is detached when
  `ns.scene.want` is false and nothing is easing out.
- Sims: `Tools/skyride-sim`, `Tools/shoulder-sim` still pass (they don't go
  through the orbit, but they load Camera.lua).
- In game (Forever, then retail), each scene once: standing still/AFK, sit
  (+ campfire), dance/kneel/sleep emotes, Hearthstone/teleport (tele), vista,
  fishing (fish camera + right-click reel), weapon drawn (cozy, hero walk),
  auto-run and RP walk (delays, mouse steer), flight (+ fly-by), death
  (tilt, Exit camera), logout countdown, quest cam, Chat Cam, a custom
  trigger, the camera wheel and key binding, Stop camera, a camera script.
  Shadow mode on for all of it; no "director mismatch" lines.

## Not in this step

- The shared facts cache (`RuleFacts`/`RowOnNow` asked ~7 times a frame).
- Moving the every-frame watchers (quest cam, depth of field, campfire sit
  button, CooldownFlash, server message watch, chat copy button, the custom
  scene checks) onto `SceneChanged` / events.
- `UpdatePlates` settled skip.

## Open questions

- 10 a second for the director: fine, or 20?
- Shadow mode dev-only (no release note, see dev-only-no-release-notes).
- One release for phases 1-4, or ship 1+2 first?
