# Showcase video: recording playbook

Made from `clips.json` by `clip.py`: don't edit by hand.

**Done 6 / 27**, skipped 13, to record 8.  
OBS records to `C:\Users\casal\Videos\Cinematic Showcase\raw` → takes go to `C:\Users\casal\Videos\Cinematic Showcase` as `C31 quest-cam t1.mp4`.

One clip at a time: set up, record in OBS, stop, then say which clip it was.
**Hub** = a Demo Hub button (`/cine demo <key>`, or Dev > Demo Commands). ★ = for the short video. NEW = added in the last days.

Before each session: Clean slate (hub), a showcase profile, Captions on for carousels and off for B-roll.

**Zoom** (how the clip is framed in the edit):

- **wide**: Full frame (only cut to the video's shape). Cameras, tints, cards, the world. Normal UI Scale.
- **medium**: Crop to about half the frame, on the area named. Normal UI Scale is fine.
- **close**: The window fills most of the frame. Record with UI Scale turned on at max (1.15) so the text is sharp, then crop to it.

## S0. Setup (1/1)

OBS test: a few seconds of WoW to check the picture, sound and that the take gets filed.

| | Clip | What | Zoom | Client | Hub | How | Takes |
|---|---|---|---|---|---|---|---|
| [x] | C00 | OBS test recording | wide | any | tints | Record ~15 seconds: run the Tint presets carousel, move the camera a little. | C00 obs-test t1.mp4 (picture ok, no sound)<br>C00 obs-test t2.mp4 (sound ok: Game Capture audio): 0:00 on the mount, hilltop · 0:04 spell flash · 0:08 flying mount takes off · 0:10 lands |

## S1. Settings & menus (4/17)

Anywhere quiet. Raise WoW's UI Scale so the text reads on video.

| | Clip | What | Zoom | Client | Hub | How | Takes |
|---|---|---|---|---|---|---|---|
| [x] | C01 | Welcome window and the three profiles ★ | close: the window | any | welcome | Click through the levels, pick Cinema, Next turns gold. | C01 welcome t1.mp4 (17s: opens, Cinema picked, no clicking through): 0:00 world, no UI · 0:03 window opens, Cinema already picked · 0:17 end<br>C01 welcome t2.mp4 (65s full take: Subtle, Balanced, Cinema, Customize pages): 0:00 window, full UI · 0:06 Subtle · 0:09 Balanced · 0:15-0:18 Cinema: UI fades · 0:21-0:24 Vitals Vision preview (Cinema picked) · 0:27 Customize: UI fade · 0:33 Action bars · 0:39 Layout · 0:42 Camera · 0:48 Look · 0:51 Visions · 0:57 Chat · 1:00 Music · 1:03 closed, world<br>C01 welcome t3.mp4 (UI Scale 1.15: window ~1000px wide, sharp. Best take: Subtle/Balanced/Cinema + 4 Customize pages): 0:00 window, full UI, nothing picked · 0:06 Subtle · 0:09 Balanced · 0:12 Cinema: UI fades · 0:12.6-0:15 Vitals Vision preview (Cinema picked) · 0:16 Next gold · 0:16.5 Customize: UI fade · 0:27 Action bars · 0:30 Layout · 0:33 Camera · 0:36 Look · 0:39 Visions · 0:42 Chat · 0:45 Music · 0:45.5 closed, world |
| [x] | C02 | Settings tour: every page | close: the window | any | tour-all | Let it run; pages change on their own. | C02 settings-tour t1.mp4: 0:08 Main page · 0:12 Profiles · 0:16 Interface (Game Frames…Chat Bubbles, 4s each) · 0:59 Nameplates · 1:07 Style (General, Unit, Raid, PRD, Tooltip, Nameplate, Names, Cast Bars, Bubbles) · 1:43 Camera (General, Scenes, Scripts) · 1:55 Atmosphere (Effects, Tint, Letterbox, Graphics+, Audio) · 2:23 Visions (Heal, Vitals, Quest, Roll, Duel) · 2:59 Cards (Events, Styles, a card, Sounds) · 3:15 Wheels (master, yours, camera, menu, marker, ground, vision) · 3:43 QoL General, Fishing · 3:52 Keybinds · 3:55 New features, All changes, Socials, Help · 4:11 Why Is It Showing (tour over; idle to 4:39) · 4:39 Esc: game menu (cut before) |
| [-] | C03 | Interface hub: new page names, Visibility/HUD/Overhead groups, the » on Game Frames rows NEW | close: the window | any |  | Open Interface, hover the icons, click a row's » to jump to its page. | skipped: covered by C02 0:16-1:07 (Interface pages, bands); » click moved to C04 |
| [x] | C04 | Settings search box, and a Game Frames row's » to its own page | close: the window | any |  | Type "tint", then "music", click a result. Then Interface > Game Frames: click a row's » (e.g. Minimap). | C04 search t1.mp4: 0:05 /cine options · 0:06 settings: main page · 0:09 search: tint results · 0:14 search cleared · 0:15 search: music results · 0:18 result clicked: lands on its setting, highlighted · 0:20 Interface > Game Frames · 0:24 row tooltips (Location, Edit as a rule) · 0:29 minimap shows (row hovered) · 0:31 Esc: game menu (cut before) · no » jump in this take |
| [x] | C05 | Menu look: HD vs SD | close: the window | any | menu-look |  | C05 menu-look t1.mp4: 0:06 3-2-1 · 0:09 lead-in (clear) · 0:11 settings: main page · 0:12 HD (flat gold boxes) · 0:15 SD (game checkmarks) · 0:18 HD · 0:21 SD · 0:24 Stop recording (cut before) · difference is only the checkboxes on this page: subtle<br>C05 menu-look t2.mp4: 0:08 lead-in · 0:09 settings: main page (not Tint: old code, no /reload?) · 0:12 HD · 0:15 SD · 0:18 HD · 0:21 SD · 0:22 Stop recording · same as t1<br>C05 menu-look t3.mp4: 0:08 lead-in · 0:11 Tint page opens · 0:13 HD: flat gold sliders and boxes · 0:16 SD: game sliders, checkmarks · 0:19 HD · 0:22 SD · 0:25 Stop recording (cut before) · best take |
| [-] | C06 | Style preview: larger preview, Pop out, drag, Dock NEW | close: the window | any |  | Style > Unit Frames: open the larger preview, Pop out, drag it, Dock. | skipped: menu detail: shown in the settings tour (C02) |
| [-] | C07 | Profiles: switch Subtle / Balanced / Cinema and watch the world change, make your own, share it ★ | close: the window | any | export, then import | Profiles page beside the world: click each built-in profile (pause on each), New profile, then Export and Import. | skipped: covered by C01 t3 (levels switched with the world changing behind) |
| [-] | C08 | Language dropdown | close: the window | any |  | Main page: switch to Deutsch, then back. | skipped: menu detail |
| [-] | C09 | Inspect (/cine why): click a frame, see why it shows | close: the Inspect popup and the frame clicked | any | why | Click a faded action bar, then the minimap. | skipped: troubleshooting tool, not a showcase feature |
| [-] | C10 | Why Is It Showing? page: every row, filters, pick a frame | close: the window | any |  | Community > Why Is It Showing?: sort, Showing/Hidden filters, Pick a frame. | skipped: menu detail: in the settings tour (C02) |
| [-] | C11 | Addon Frames: Loaded/Unloaded tabs, Hover Find, Smart Find | close: the window | any |  | With an extra addon loaded: Find frames tab, Hover Find a frame, run Smart Find. | skipped: menu detail: in the settings tour (C02) |
| [-] | C12 | Minimap button menu and tooltip | close: the minimap button and its menu | any |  | Hover, then right-click the minimap button. | skipped: menu detail |
| [-] | C13 | Cameras page: copy a camera, rename, pick its icon | close: the window | any |  | Right-click a camera > Copy, rename it, choose an icon from the browser. | skipped: menu detail: Cameras page in the settings tour (C02) |
| [-] | C14 | Camera Scripts: steps, Play step, run and Stop | close: the window | any |  | Open a built-in script, add a step, press Play, then Stop. | skipped: menu detail: Scripts page in the settings tour (C02) |
| [-] | C15 | Wheels: camera wheel, then the menu, marker and vision wheels ★ | medium: the wheel round the cursor | any | wheel | Cursor mid-screen. Hold each wheel's key in turn; start a camera from the camera wheel. | skipped: in a section |
| [-] | C16 | Menu, marker, ground marker and vision wheels | medium: the wheel round the cursor | any |  | Hold each wheel's key in turn, open a window from the menu wheel. | skipped: merged into C15 |
| [-] | C17 | What's new page and the update notice | close: the window | any | whatsnew, update-notice |  | skipped: menu detail: in the settings tour (C02) |

## R. Sections (1/9)

One recording per section: follow its route in order without stopping; I mark each feature in the take afterwards. A section can be split over takes if something goes wrong (t1, t2…).

| | Clip | What | Zoom | Client | Hub | How | Takes |
|---|---|---|---|---|---|---|---|
| [ ] | R1 | City and inn ★ | wide | any |  | A busy capital, ending in its inn. CineMode off at the start. About 6–8 min.<br>1. Stand at a nice street spot, UI showing: `/cine demo hook` (UI fades, letterbox in), then `/cine demo hook-back`<br>2. Hover the action bars, then the minimap (hover reveal, its group comes up)<br>3. `/cine demo chat-peek`, then `/cine demo speech` (chat pops up, speech from behind)<br>4. Walk through the crowd past chatty NPCs (nameplates by kind, text-only bubbles)<br>5. Target a player and hover them (styled target frame, tooltip)<br>6. Cast a self-buff or a weapon enchant (buff peek)<br>7. Talk to a quest giver, read, accept (Quest Cam, Quest Vision)<br>8. Walk mode + auto-run down the main street (RP Walk Cam)<br>9. Walk into the inn (Rested card, inn glow)<br>10. `/cine demo cozy-tour`, then sit in a chair, then stand and draw your weapon (Cozy Cam) |  |
| [ ] | R2 | Travel: flight, mount, Hearthstone ★ | wide | any |  | A flight master, on a route you've flown before. About 3–5 min.<br>1. `/cine demo flight-director`, then take the flight (Flight Cam, fly-bys)<br>2. Land (settling camera, Flight arrival card, zone card)<br>3. Mount up and auto-run down a road (Auto-run Cam; skyriding on retail)<br>4. Stop, Hearthstone (Tele Cam, Tele Vision) |  |
| [ ] | R3 | Questing and combat ★ | wide | any |  | A low-level zone with an unfinished kill/collect quest. About 4–6 min.<br>1. Tracking on, ride toward the quest area past a node (minimap stays up)<br>2. Look over the quest mobs and objects (quest marks)<br>3. Pull one mob (combat frames, combat cards and sound, Cooldown Manager on retail, then it all fades)<br>4. Pull several and let your health drop (Vitals Vision)<br>5. Die (Death Cam, its song, Death card) |  |
| [x] | R4 | Reel: the look ★ | wide | any | reel-look | Somewhere pretty with a view, ideally near dusk. One button, ~6 min, stand still.<br>1. `/cine demo reel-look`: tints, zone moods, vignette, depth of field, letterbox, time of day, golden hour, moonlight, Vista Cam | R4 reel-look t1.mp4: 0:00 UI, run typed · 0:08 3-2-1, lead-in · 0:12 Tints: none, warm, cool, night, dusk, sepia, dreamy (4s each) · 0:39.6 UI flashes for a frame (cut) · 0:42 Zone moods (subtle here: the zone is already gold) · ~1:37 Vignette sweep · ~1:49 Depth of field · ~2:00 Letterbox sweep: no bars visible (fixed in code) · 2:06 Time of day sweep, camera circling (titles Dawn 2:40, Morning 2:48, Evening 3:04, Dusk 3:12) · 3:24 Golden hour B-roll · 4:00 Moonlight B-roll · 4:32 Vista Cam · 4:48 Stop recording: CUT HERE · 4:56-7:28 idle, game AFK camera (unused) |
| [ ] | R5 | Reel: visions and cards | wide | any | reel-visions | Anywhere. One button, ~5 min, stand still.<br>1. `/cine demo reel-visions`: Tele Vision, Vitals Vision fall + themes, every card, Damage Vision (if loaded) |  |
| [ ] | R6 | Outdoors: wheels, fishing, campfire | wide | any |  | By water with a campfire nearby. About 3–4 min.<br>1. Cursor mid-screen: hold the camera wheel key, start a camera; then the menu, marker and vision wheels<br>2. Fish, recast with right-click (Fish Cam)<br>3. Hover the campfire, click the icon at the cursor (Campfire button, Cozy Cam)<br>4. Any time it rains or snows: record a bit (weather tint) |  |
| [ ] | R7 | Group | medium | any |  | With a friend or two. Whenever you can.<br>1. A few pulls in a party (Heal Vision on the party frames)<br>2. Ready check<br>3. A loot roll (Roll Vision)<br>4. Mark mobs from the marker wheel<br>5. Duel your friend near other duels (Duel card, Duel Vision) |  |
| [ ] | R8 | Other addons fade too | wide | any | hook | Anywhere, one addon loaded per take.<br>1. `/cine demo hook` once each with Details!, Bartender4, Plater, EllesmereUI, FlareUI, DaylightUI, Questie, RestedXP |  |
| [ ] | R9 | Classic extras | medium | classic |  | Classic Era, on a hunter.<br>1. Melee a mob (swing timer)<br>2. Right-click mobs in and out of a fight (target + Auto Shot)<br>3. Ammo vendor: Fill quiver |  |

## Edits to make from these

1. **All features** (first): each section in order, cut down to its marked moments.
2. **Short videos (1-2)**: the best moments from the ★ sections: open on the hook (R1), end on the B-roll (R4).
3. **In-depth video**: all clips plus settings close-ups (S1) per feature.
