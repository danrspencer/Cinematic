# Camera audit: the logic you can't see (2026-11-07)

Every camera plays a script now. Some of what a scene does comes from
the script you can see on the Cameras page; the rest is written in the code.
This lists the parts written in the code, where they live, and what to do
with each.

Each item is marked:

- **Expose**: changes what you see, so it should be a setting, a rule or a
  trigger part you can change.
- **Show**: a fixed fact, so say it on the page (a line of text, a tooltip,
  the live log).
- **Keep**: works around the game engine (jolts, speed settings), so it stays
  in the code. Explain it in one help box, not in sliders.

---

## 1. What you can already see and change

- **Scene rows** (Cameras page): the camera, Music, CineMode, When (Show in
  ticks, rule, roles), Wait for the Calm Timer.
- **Script steps** and **When it ends**, on the camera's page. A built-in
  camera's steps show their values but are fixed: Copy one to edit it.
- **Stop rules** on every script: Your camera input, A fight, Walking, Your
  zoom, The trigger ends, Your cast ends. Each has its actions (Stop, Put
  back, Pause, Restart, Ignore).
- **Your own triggers** (Triggers page): what starts it, Only if, what ends
  it, Delay, Hold, Cooldown, Chance, Priority.
- **Built-in triggers** (Hearthstone, AFK, the emotes...) are listed on the
  Triggers page with their priority only. TriggerLibrary.lua says it
  outright: "their other parts are still written into the cameras' code".
  That's most of this audit.

---

## 2. The script player: rules every script follows

`CameraScripts.lua`, the watcher and `Update`.

| # | Hidden rule | Mark |
|---|---|---|
| P1 | **No start in a fight.** A scene whose trigger comes on during a fight waits. It starts once the fight's over if the trigger is still on, and otherwise never. | Show |
| P2 | **Stopped means stopped for this time.** Once you stop a scene (your camera input with rule Stop, the Stop button...), it won't start again until its trigger has ended and come back. | Expose: a "Can start again: after the trigger ends / after N sec" choice |
| P3 | ✅ **Done: rule *A window opens*.** **Open windows hold every scene** where it is until they close (Scenes page's Pause cameras in windows). Which windows count (NPC windows, the game menu, bags?...) isn't listed anywhere. Quest and interaction scenes are exempt. | Show the list. Expose as a rule: **A window opens**: Pause / Ignore / Put back |
| P4 | ✅ **Done: rule *Its quest window closes* (Pause 3 s by default).** **Quest window closed: hold** (added today). A quest script holds still from the moment you accept or hand in, until the conversation ends 3 s later, or carries on if the next window opens. | Expose as a rule: **Window closes**: Pause (secs) / Ignore / Put back. Replaces today's hard-coded hold |
| P5 | ✅ **Done: rule *Its steps run out*.** **Out of steps: hold.** A scene played for a trigger that runs out of steps (no Repeat at the end) holds where it got to until the trigger ends. Played by hand, it plays When it ends straight away. | Expose as a rule: **Steps run out**: Hold / Put back |
| P6 | **Handover.** If another trigger comes on that uses the same camera (the Campfire button's sit giving way to the campfire buff), the scene carries on for it instead of putting back and starting over. | Show |
| P7 | **Your zoom becomes your distance.** Zoom yourself while a scene plays, and 0.4 s after the camera settles that's the distance When it ends zooms back to. | Show (it's what people expect; one line) |
| P8 | **Walking means walking by hand.** Auto-run and auto-walk never trigger the Walking rule. Travel scenes (mounted, flying, swimming, Skyriding) ignore Walking, and your camera input stops only their turns and tilts, not their zoom. | Show. Expose "travel scene" as a tick on the scene |
| P9 | **When it ends can only be stopped** by your camera input or a fight. Walking, your zoom, the trigger... are ignored once it's going back. | Show |
| P10 | **Your zoom always wins** over the script's zoom, even with Your zoom set to Ignore (Ignore means the rest of the script carries on). | Show: rename Ignore to "Carry on" for that rule |
| P11 | **Camera follow is off** while any script plays (the game's own swing-behind is switched off). | Show |
| P12 | **Which scene wins** when several triggers are on: your key scene, then an interaction scene, a travel scene, Skyriding, the standing-still triggers (by the Triggers page priority), then Flight, Death, RP walk, Auto-run, Quest, Chat, in that fixed order. Only the standing-still group follows the priority list. | Expose: one priority list for all of them |
| P13 | **Timing of moves:** 0.6 s between one turn or tilt and the next, 1 s shortest move, 0.5 s shortest zoom, 1.2 s brake when a Wait until cuts steps short, the speed creep at each start. | Keep (help box) |

---

## 3. Built-in triggers: when they start and end

Your own triggers have Delay, Hold, Cooldown, Chance and Only if. Built-in
ones only get them in the standing-still group (`Triggers.lua` Gate). Flight,
Death, RP walk, Auto-run, Quest and Chat skip the gate entirely
(`TriggerNow` in CameraScripts.lua).

### Quest / Talk about a quest (`QuestCam.lua`)

| What | Value | Setting? | Mark |
|---|---|---|---|
| Wait before starting | questCamDelay / questCamGossipDelay | yes | |
| Each window after the first adds | **1 s** (WINDOW_EXTRA) | no | Expose |
| Ends after the last window closes | **3 s** (CLOSE_GRACE) | no | Expose ("Hold after the window closes") |
| "You left" (Escape, Goodbye): ends at once | no accept/pick within **2 s** before the close (LEAVE_WINDOW) | no | Show |
| Another quest giver near: the scene stays on | minimap mark within **28 yd** (GIVER_NEAR) | no | Expose |
| ...until you walk off | **10 yd** from where you talked, or **1.5 s** walking where the game won't say where you are | no | Expose |
| Walking off with the window open ends it, for the rest of the talk | always | no | Show |
| Won't start while moving | always | no | Show |
| Not for quests shared by a player or from an item | always | no | Show |
| Not mounted / not dailies / every NPC counts | questCamNotMounted, questCamNotDaily, questCamAllGossip | yes | |
| Start distance carried over from the last quest giver (zoom back held) | always | no | Show |

### Chat / Chat nearby (`CameraScripts.lua` heardFrame, `ChatCam.lua`)

| What | Value | Setting? | Mark |
|---|---|---|---|
| Conversation over after quiet | chatCamQuiet | yes | |
| A line counts as "Chat" (not Nearby) if: a party NPC, your target, or an NPC whose window closed less than **30 s** ago (TALKED_WINDOW) | 30 s | no | Expose |
| Nearby needs you standing still | chatNearbyDelay | yes | |
| No start while moving | always | no | Show |
| Cities' Nearby unticked to start with | default | yes | |

### Flight, Skyriding, RP walk, Auto-run, Death

| Trigger | Hidden part | Mark |
|---|---|---|
| Flight | On from takeoff to landing. The script's "settle" starts taxiSettleLead **+ 12 s + 3 s** before landing (time for the 12 s turn back and the 3 s zoom). The +15 is baked in | Show, or work it out from the steps |
| Skyriding | Off once you've been down skyrideCamLand + the back time **+ 0.5 s** | Keep |
| RP walk / Auto-run | Delay sliders are settings. Turning by hand pauses the start **0.6 s** (old camera code) | Show |
| Death | Death Cam page's conditions. Calm Timer never applies | Show |

### Standing-still triggers (`Camera.lua` CurrentEvent)

| Trigger | Starts | Ends | Hidden |
|---|---|---|---|
| Sit, Sleep, Dance, Kneel, Stare | the emote (Sleep also /laydown, /lie) | you move, jump or do another emote | which emote words count. Expose: list them on the trigger |
| Chair | sitting in a seat | as above | Show |
| Campfire button | sitting with Campfire's Sit button | as above | Show |
| Weapon | drawn with the sheathe key, calmly | put away; moving stops it until drawn again | **hero walk**: with RP walk and the Cozy camera it carries on as you walk. Show |
| Campfire | a listed buff | buff gone; moving stops it till you get it again | sitting by the fire beats every emote, standing by it loses to them. Show |
| AFK | flagged AFK | back; moving or turning with the keys stops it | turning stops AFK only, not Weapon/Campfire. Show |
| Hearthstone / Teleport | the cast (by spell ID, or a name containing "Hearthstone" / "Teleport:") | cast done or cancelled | cast length unreadable: assumes **10 s**. Show |
| Fishing | Fishing channel | you move or jump (carries on through looting, recasting) | Show |
| Log out | the 20 s countdown | moving, casting, the countdown box gone (after **1 s**), or **22 s** | Show |
| Stand still | idleOrbitDelay | moving | (setting) |
| All of them | | moving by hand ends every one, even the ones that carry on through moving | Show |

---

## 4. Built-in cameras: values baked into their steps

These show up as steps, so they're visible, but they're fixed unless you
copy the camera. Values not tied to a setting:

- **Tele camera**: half turn 180° over 5 s, tilt over 5 s, spin starting at
  48°/s for 5 s, zoom over 10 s.
- **Flight camera**: zoom back 3 s, put back 12 s (settle), zoom on landing 3 s.
- **Death camera**: tilt over 6 s, zoom over 8 s, spin speeds up at 2°/s²,
  camera input pauses it 5 s, put back 2 s.
- **Fly-by**: wait 1 s, put back 1.5 s before the turn.
- **Quest / Chat**: When it ends turns back over 4 s; drift legs 7 s each.
- **AFK**: put back 4 s. The turn's time is worked out from Step, Speed and Ease.

Mark: Show. If people want them, make them settings on the camera's page,
like the others.

---

## 5. Dead weight

Now that every camera plays its script, the old code-driven cameras
(QuestCam.lua's own swing/turn/tilt/drift, ChatCam.lua's aim and tracking,
Camera.lua's orbits) still carry about 150 tuning constants. Most no longer
move the camera for anyone. They hide nothing but make the code hard to
audit. Worth a separate pass to check what's still reachable and remove the
rest.

---

## 6. Proposed plan, in order

1. ✅ **Done 2026-11-07, untested in game.** **New stop rules** on every script: *A window opens*, *Window closes*
   (with seconds), *Steps run out*. Move today's quest hold and the global
   window pause (P3, P4, P5) into them, with defaults that do what happens
   now. Nothing changes until you change a rule.
2. **Built-in triggers get the full trigger parts** on the Triggers page:
   Delay, Hold, Cooldown, Chance, Only if for all of them (Flight, Quest,
   Chat... too), plus their own numbers from section 3 marked Expose (Quest:
   hold after close, extra per window, giver range, walk-off distance; Chat:
   talked window).
3. **One priority list** for every trigger (P12).
4. **"Starts / Ends" text** on each built-in trigger's page, written from
   section 3, so the Show items are read on the page and not guessed.
5. **Live "why" line** on the scene/camera page and in `/cine why`:
   "Quest camera: held, window closed, ends in 2.1 s". The player already
   knows each state (pausedBy, phase, trigger on).
6. A help box for the Keep items (P13).
7. Later: remove the old non-script camera code (section 5).
