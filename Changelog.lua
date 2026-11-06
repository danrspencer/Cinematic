-- What's new > New features: the changes worth telling players about, each
-- added by hand (with the user's OK) as it's committed. Newest first by date
-- on the page, whatever the order here.
--   date    when it went in (YYYY-MM-DD)
--   title   a few words; text: a sentence or two, for players
--   page    the settings page it's on (English name, as ns.OpenOptions takes
--           it), for its icon and a Show me button; nil for none
--   client  "forever" or "retail": only listed on that client
-- Title and text go through L like the rest, so add them to esES.lua too.
-- (Every commit is on the All changes page, from ChangelogCommits.lua.)
local _, ns = ...

ns.CHANGELOG_FEATURES = {
	{ date = "2026-11-06", page = "General", title = "Chat history",
		text = "Tick Keep chat history on the Quality of life page and your chat windows bring back their last 200 lines " ..
		"after a reload or login, for up to a day, with the time each was said if you like." },
	{ date = "2026-11-06", page = "Style Overrides", title = "Style overrides",
		text = "Hide or show parts of the unit frames and nameplates from one tab, whatever their Interface rows say. Themes can use it too, and an overridden row says so." },
	{ date = "2026-11-05", page = "Style General", title = "Style themes",
		text = "A whole new look in one click: Silver Screen, Gilded Codex, Emberforge, Moonlit Glade and Frostbound " ..
		"each change your frames, fonts, panels and menus. Pick one on the Style hub's General page." },
	{ date = "2026-11-05", page = "Skyriding Cam", title = "Skyriding Cam", client = "retail",
		text = "Skyriding gets a camera of its own: it pulls back as you take off, tilts as you climb and dive, " ..
		"follows your turns, and answers Surge Forward, Skyward Ascent, Whirling Surge and Aerial Halt. Set each " ..
		"moment on its page." },
	{ date = "2026-11-05", page = "Triggers", title = "Triggers page",
		text = "Every trigger in one place, in the Camera hub: make your own and set what starts it, what ends it, " ..
		"an Only if rule, its timing and its priority, then use it in any scene. Ours take an Only if, timing and " ..
		"a priority of their own too." },
	{ date = "2026-11-05", page = "Nameplates", title = "Service NPCs",
		text = "In CineMode, vendors, trainers, flight masters, innkeepers and other NPCs with a title keep their " ..
		"names on their nameplates while guards and townsfolk stay hidden. Pick which kinds count, or show just " ..
		"their titles (<Repair Vendor>) in place of their names." },
	{ date = "2026-11-04", page = "Cursor Hide", title = "Cursor Hide (experimental)",
		text = "In CineMode, your cursor gets out of the way: it shrinks to a tiny corner, vanishes once the mouse " ..
		"has been still a while, or both. Moving the mouse brings it back. It's experimental: accept the warning " ..
		"on its page to turn it on, and /cine reset cursor puts your cursor back if it ever gets stuck. The " ..
		"Cinema profile uses it during flights, at vistas and while you're AFK." },
	{ date = "2026-11-04", page = "Vitals Style", title = "Game effect themes", client = "retail",
		text = "Six new Vitals Vision themes are built from the game's own full-screen effects, moving and closing " ..
		"in as your health drops: Cosmic void, Hellfire, Radiance, Frostbite, Fel flames and Spellfire. Find them " ..
		"under More themes." },
	{ date = "2026-11-03", page = "Emote Vision", title = "Emote Vision",
		text = "When someone buffs you, raises you, emotes at you, summons you or trades with you, or your group " ..
		"kills a boss or levels up, a small card shows who it was, with emotes to answer in one click. Pick each " ..
		"moment's emotes (voice ones too) and one of six card styles." },
	{ date = "2026-11-02", page = "Teleport Vision", title = "Tele Vision",
		text = "As you cast your Hearthstone, Astral Recall or a teleport, a portal opens around you in your class " ..
		"and spec's color, closing in as the cast fills, then the screen goes black as you're whisked away. It " ..
		"plays alongside the tele camera." },
	{ date = "2026-11-02", page = "Card Vision", title = "Story cards",
		text = "The Cards page has 13 new moments: level up, places discovered, flight arrivals, inns, " ..
		"achievements, reputation, new mounts and pets, profession ranks, story quests, dungeons cleared, rares, " ..
		"battlegrounds and kill streaks. Every card now belongs to one of four looks, so they match out of the box." },
	{ date = "2026-11-02", page = "Vitals Style", title = "Vitals swirls",
		text = "Vitals Vision's themes now have spiral arms turning over the screen as your health drops, " ..
		"quicker the weaker you are. Set them on the Style page's new Swirl tab, or try the swirl themes under " ..
		"More themes: Vortex, Abyss and Dungeon portal." },
	{ date = "2026-11-02", page = "Damage Vision", title = "Damage Vision",
		text = "Instead of damage meter numbers, see your race with #1 (or your lead over #2) as a bar, a race " ..
		"track or a ladder, plus a recap of how you did after each boss and dungeon." },
	{ date = "2026-11-01", page = "Advanced Frames", title = "Smart Find",
		text = "The Addon Frames page's Find frames tab can look for other addons' frames that nothing " ..
		"fades, say which addon made each and guess which row it should follow. Add them with a click." },
	{ date = "2026-11-01", page = "Why showing", title = "Why is it showing?",
		text = "Type /cine why, or pick it from the minimap button's menu, then click any frame to see why it's " ..
		"showing or hidden right now and which settings say so. It works on other addons' frames, Cinematic's " ..
		"own (like quest talk), and the last tooltip too. The Why Is It Showing? page in Community lists every " ..
		"row of frames at once." },
	{ date = "2026-10-31", page = "Cameras", title = "Every camera at a glance",
		text = "The Camera hub's General page now shows every camera, built in and yours, as an icon. Click one " ..
		"to open a tab with its script and the scenes that play it, and jump straight to either." },
	{ date = "2026-10-31", page = "Camera Scripts", title = "Camera scripts",
		text = "Every camera is now a script of steps (turn, zoom, sway, wait, follow...) on the new Scripts " ..
		"page in the Camera hub. Pick one to see how it moves, change its steps and settings there, or copy it " ..
		"to make a camera of your own." },
	{ date = "2026-10-31", page = "Story Vision", title = "Story Vision",
		text = "A new Vision for the words that fade in on your screen between fights: what you did last time " ..
		"as you log in (\"Last time: Darkshore · 3 quests done · reached level 24\"), the time of day, a place " ..
		"under attack, and the death banner, each with its own tick and a Test button. Combat Vision is now " ..
		"called Battle Vision." },
	{ date = "2026-10-31", page = "Scenes", title = "Scenes and shots of your own",
		text = "Make your own camera scenes on the Scenes page: an emote, a spell, a buff, a place, a moment or " ..
		"a key can start one, and a scene can have several triggers. The built-in ones are grouped by camera and " ..
		"take triggers of yours too. On My Shots, set how a camera sways and zooms, and share either with a " ..
		"friend." },
	{ date = "2026-10-30", page = "Help", title = "Help page",
		text = "Links to the guidebook, troubleshooting and the bug report form, how to send your log with " ..
		"/cine log, and the Profiler for a slow game, together in Community." },
	{ date = "2026-10-30", page = "Profiler", title = "Profiler",
		text = "See how much of your computer's time Cinematic takes, as a graph of the last five minutes, and " ..
		"record a while of play to see which parts cost the most. If Cinematic feels slow, Copy report and " ..
		"send it to us." },
	{ date = "2026-10-30", page = "Vitals Style", title = "Your own Vitals themes",
		text = "Change any Vitals Vision theme's art, colors, sparks and heartbeat, or make themes of your own " ..
		"from one, and rename or delete them. Reset theme puts one of ours back as it comes." },
	{ date = "2026-10-30", page = "Advanced Frames", title = "Find frames to fade",
		text = "Type part of a frame's name, or of the addon that made it, to find frames to fade. Hover a " ..
		"match to see it marked on screen, then click it to fade it." },
	{ date = "2026-10-30", page = "Profiles", title = "Profile backups",
		text = "Your own profiles are backed up once a day when they change and just before Delete or Reset, " ..
		"and deleted ones are kept for 30 days. Bring one back with Backups on the Profiles page." },
	{ date = "2026-10-30", page = "Combat Vision", title = "Boss cards",
		text = "A boss's name as a title card, as its fight starts or as you first target it or come near: on " ..
		"the screen, in a letterbox bar or low on the left like a film, with its dungeon and which boss it is. " ..
		"Its look has its own tab on Battle Vision's Style page." },
	{ date = "2026-10-29", page = "Cameras", title = "Chat Cam",
		text = "As NPCs talk, the camera zooms in and turns to whoever's speaking, then turns back and zooms " ..
		"out once they're done. On in the Cinema profile; turn it on for NPCs you talk to or those chatting " ..
		"nearby on the Cameras page." },
	{ date = "2026-10-29", page = "Personal Resources", title = "Mana cost",
		text = "While you cast, the mana a spell will take shows as a pale stretch on your mana bar, and its " ..
		"numbers can show what you'll have left." },
	{ date = "2026-10-29", page = "General", title = "Reload button",
		text = "A Reload button on the screen and a key to reload the UI in one go, and after any reload the " ..
		"windows you had open (these settings at your page, bags, map, the game's windows) open again." },
	{ date = "2026-10-29", page = "Style General", title = "Style hub",
		text = "A page for the look of each part of your UI: unit, raid and arena frames, the bars under your " ..
		"character, cast bars, tooltips, chat bubbles, quest talk, the loot roll window, the quest item button " ..
		"and the letterbox, each with presets and a preview. A General page sets one bar texture, font and " ..
		"border they all follow." },
	{ date = "2026-10-29", page = "Combat Vision", title = "Battle Vision",
		text = "A cue as you go into a fight and come out of it: a word on the screen or in a letterbox bar, a " ..
		"pulse around the edges, an icon, and sounds you pick for each kind of fight, like horns for a raid boss. " ..
		"Its look has a page in the Style hub, with presets and a preview." },
	{ date = "2026-10-28", page = "Scenes", title = "Cameras page",
		text = "Camera Modes and Camera Triggers are now one Cameras page: a row for each trigger (an emote, " ..
		"a campfire, going AFK, a flight...) with the camera it starts, its music and CineMode, and where it " ..
		"can start. Copy a row to give a trigger a different camera in other places." },
	{ date = "2026-10-28", page = "Socials", title = "Socials",
		text = "A new page in the Community hub with links to the Discord, YouTube, CurseForge and GitHub, " ..
		"ready to copy." },
	{ date = "2026-10-27", page = "Nameplate Style", title = "Nameplate marks",
		text = "Marks and colors for your focus, the unit under the mouse and a target that's attacking you, " ..
		"not just your target, each with its own look, when it shows, and rows for just enemies or friends. " ..
		"Set them on the Style hub's Nameplates page." },
	{ date = "2026-10-27", page = "Name Style", title = "Name styles",
		text = "The names Cinematic draws on faded nameplates in CineMode have a page of their own: their " ..
		"colors, outline, opacity, size and height, with presets and a preview." },
	{ date = "2026-10-27", page = "Profiles", title = "A new welcome window",
		text = "Pick how much Cinematic does, Subtle, Balanced or Cinema, then Customize changes one part " ..
		"at a time: your layout, camera, look, Visions, chat and sound." },
	{ date = "2026-10-26", page = "Personal Resources", title = "Resource Display page",
		text = "Your player frame, pet frame and resource display have a page of their own: kept up while you " ..
		"recover or run low on mana, and held back at the start of a fight until your power changes." },
	{ date = "2026-10-26", page = "Nameplate Style", title = "Target Arrow",
		text = "A mark on your target's nameplate for when no target frame shows who you've got: an arrow, " ..
		"chevron, glow or brackets, colored by how they see you." },
	{ date = "2026-10-26", page = "Quest Vision", title = "Quest talk",
		text = "Talking to an NPC, their words show in a speech bubble over their head and your replies in a " ..
		"list below, instead of the game's gossip and quest windows. Pick a reply with 1-9, and Space to read on." },
	{ date = "2026-10-26", page = "Standard Frames", title = "New settings grids",
		text = "Every grid now has the same row: Always, then Combat, Target and Location dropdowns, Roles and " ..
		"Edit. Edit turns a row into a rule, for AND, NOT, Cities and more, with a dot showing whether it's on " ..
		"right now. Chat bubbles, tooltips, effects, music and the cameras now say where they show instead of " ..
		"where they hide." },
	{ date = "2026-10-26", title = "Menu look",
		text = "Pick HD or SD for Cinematic's settings and windows on the main page: flat and dark, or the " ..
		"game's own look. Auto follows your client, and your Character Models setting on WoW Forever." },
	{ date = "2026-10-26", page = "Your wheels", title = "Share wheels",
		text = "Share a wheel of yours as a line of text and import one from a friend, reading every command " ..
		"first. Icons now come from every icon the game has, like the macro window's, and you can add icons " ..
		"of your own to the marker and vision wheels." },
	{ date = "2026-10-26", page = "Master wheel", title = "Wheels page",
		text = "A new Wheels page shows every wheel and its icons, with its keybind right there, and lets you " ..
		"pick which wheels sit on the master wheel and in what order." },
	{ date = "2026-10-24", page = "Vitals Vision", title = "Vitals Vision",
		text = "As your health drops, dark edges creep in around the screen with art themed to your class " ..
		"and talents (blood, frost, fire...), a heartbeat that quickens and a flash on big hits, so you can " ..
		"tell how you're doing at a glance." },
	{ date = "2026-10-23", page = "Chat", title = "Speech from behind you",
		text = "Tick Show speech from behind you on the Chat page and says and yells from people behind you " ..
		"or out of view show as bubbles low on the screen, rising up from below, instead of bringing up chat." },
	{ date = "2026-10-23", page = "General", title = "Copy chat",
		text = "Tick Copy chat button on the Quality of life page and a small icon in a chat window's corner " ..
		"opens its lines, ready to select and copy with Ctrl+C." },
	{ date = "2026-10-23", page = "Advanced Frames", client = "forever", title = "Naowh Forever support",
		text = "Naowh Forever's top bar now fades in CineMode (a row on the Addon Frames page), and its " ..
		"RestedXP guide window fades with the Quest tracker row." },
	{ date = "2026-10-23", page = "Heal Vision", title = "Vision Helper",
		text = "The minimap button glows while a vision is doing something, and its menu lists the visions in " ..
		"use with a link to each one's page." },
	{ date = "2026-10-23", page = "Advanced Frames", title = "ElvUI, DBM and RestedXP support",
		text = "ElvUI's frames, Deadly Boss Mods' timer bars and RestedXP's guide window now fade in CineMode: " ..
		"ElvUI's following the Game Frames rows of the frames they replace, RestedXP's with the Quest " ..
		"tracker row." },
	{ date = "2026-10-23", page = "Nameplates", title = "Names on faded nameplates",
		text = "Names kept up over faded nameplates in CineMode now look like the game's own names over " ..
		"heads: colored by who they are, and smaller further off." },
	{ date = "2026-10-23", page = "Keybinds", title = "Vision wheel",
		text = "Hold a key to bring up a wheel of the visions and turn Heal, Quest, Duel or Roll Vision on or " ..
		"off, even in a fight. It's on the master wheel too, and each vision has a toggle key of its own on " ..
		"the Keybinds page." },
	{ date = "2026-10-22", page = "Roll Vision", title = "Roll Vision",
		text = "In a group, a window shows each item being rolled on, with everyone's pick and roll and the " ..
		"winner on top, so you needn't read the rolls in chat. Turn it off in the Visions page." },
	{ date = "2026-10-21", page = "Quest Vision", title = "Quest Vision",
		text = "Mobs and NPCs you still need for a quest keep their nameplates up, with a golden ! on their " ..
		"plate and your target frame. Optionally, the quest object in front of you glows so it's easy to spot." },
	{ date = "2026-10-21", page = "Keybinds", title = "Marker wheels",
		text = "Hold a key to bring up a wheel of raid markers and put one on your target, or drop a ground " ..
		"marker where you let go. A master wheel opens any of the wheels from one key. Set the keys on the " ..
		"Keybinds page." },
	{ date = "2026-10-21", page = "Profiles", client = "forever", title = "Retail profile",
		text = "A new Retail profile gives WoW Forever retail's look: Cinematic's own Edit Mode layout, with " ..
		"action bars 1 to 3, the micro menu and bags, and the XP bar each coming up on its own. Switch back " ..
		"to Default and your own layout returns." },
	{ date = "2026-10-20", page = "General", client = "forever", title = "Talent calculator",
		text = "A calculator button on your talents window opens a talent planner that looks just like it, " ..
		"starting from your talents. Plan a build, see the level it needs, then copy it over to your talents " ..
		"window to apply." },
	{ date = "2026-10-20", page = "Heal Vision", title = "Heal Vision",
		text = "The party and raid frames show only who needs healing. Pick where it works on the Heal Vision page." },
	{ date = "2026-10-19", page = "Advanced Frames", title = "Custom Visibility Rules",
		text = "Give any frame, nameplate row or unit frame part a rule of its own instead of its ticks, like " ..
		"\"In combat AND (Open World OR BGs & Arenas)\". Click Edit on its row to build it with buttons." },
	{ date = "2026-10-19", page = "Advanced Frames", title = "FlareUI support",
		text = "FlareUI's unit frames, resource bars, buffs, quest tracker, party and raid frames fade in " ..
		"CineMode, following the Game Frames rows of the frames they replace." },
	{ date = "2026-10-19", page = "Minimap", title = "Minimap Reveal",
		text = "The faded minimap comes up when ore, herbs or treasure show on it, a quest of yours is " ..
		"done, or another icon appears, with a ping on the node if you like." },
	{ date = "2026-10-17", page = "Advanced Frames", title = "WeakAuras support",
		text = "WeakAuras' auras fade in CineMode; auras anchored to another frame fade with that frame." },
	{ date = "2026-10-17", page = "Advanced Frames", title = "Questie support",
		text = "Questie's quest tracker and its quest item buttons fade with the Quest tracker row." },
	{ date = "2026-10-17", page = "Unit Frames", title = "Unit frame parts",
		text = "Pick which parts of your frame and the target and focus frames show (portrait, name, " ..
		"level, frame art) for you and each kind of unit, to keep just the bars." },
	{ date = "2026-10-17", page = "Chat", title = "Update notices",
		text = "After an update with new features, a line in chat at login says so, with a link to " ..
		"What's new. Turn it off on the Chat page." },
	{ date = "2026-10-17", page = "Advanced Frames", title = "Horizon Suite support",
		text = "Horizon Suite's quest tracker fades with the Quest tracker row, without flickering on zone changes." },
	{ date = "2026-10-17", page = "New features", title = "What's new",
		text = "The last settings page lists new features, newest first, and every change made to Cinematic." },
	{ date = "2026-10-17", page = "UI Manager", title = "Settings in hubs",
		text = "Interface, Camera and Quality of life hold their pages behind a row of icons, " ..
		"with one search box for all of them." },
	{ date = "2026-10-16", page = "General", client = "forever", title = "Talents button when inspecting",
		text = "A button on the inspect window opens the player's talents, and one on the talents " ..
		"window takes you back." },
	{ date = "2026-10-16", page = "Graphics+", title = "Graphics+",
		text = "The game's own graphics settings one by one, past what its Graphics menu allows: " ..
		"ground clutter, view distance and more." },
	{ date = "2026-10-16", page = "Nameplates", title = "Duel Vision",
		text = "In CineMode the two players in a duel near you get their nameplates, each duel with its " ..
		"own color border and class icons." },
	{ date = "2026-10-16", page = "Chat", title = "Attacks on the screen",
		text = "\"Dun Algaz is under attack!\" shows in red where the zone name appears, with your " ..
		"faction's city bell." },
	{ date = "2026-10-16", page = "General", title = "Windows you can move",
		text = "The game's windows open in the middle of the screen, can be dragged by their title bar " ..
		"and open where you last dropped them. The backpack too." },
	{ date = "2026-10-16", page = "Nameplates", title = "Plate Parts",
		text = "A grid that shows or hides each part of the nameplates in CineMode: health bar, name, " ..
		"cast bar, buffs, level and more." },
	{ date = "2026-10-16", title = "Reset addon",
		text = "A button on the main page puts Cinematic back to a fresh install." },
	{ date = "2026-10-15", page = "Keybinds", title = "Menu wheel",
		text = "Hold a key for a ring of the game's menus: character, spellbook, bags and the rest." },
	{ date = "2026-10-15", page = "General", title = "Drag to equip",
		text = "Picking up a piece of gear opens the character window, ready to drop it on." },
	{ date = "2026-10-15", page = "Hunter", client = "forever", title = "Hunter helpers",
		text = "Smallest ammo stack first after Clean Up Bags, and a Fill quiver button at vendors." },
	{ date = "2026-10-15", page = "Keybinds", title = "Camera wheel",
		text = "Hold a key to pick a camera from a ring of icons." },
	{ date = "2026-10-14", page = "General", title = "Campfire Sit button",
		text = "By a campfire a button lets you sit, kneel or lie down, with a cozy camera of its own." },
	{ date = "2026-10-14", page = "Chat bubbles", title = "Chat bubbles page",
		text = "Hide chat bubbles by place, show just their text, and set its size." },
	{ date = "2026-10-14", page = "Profiles", title = "Share profiles",
		text = "Export a profile as a line of text for a friend to import." },
	{ date = "2026-10-14", title = "Ten languages",
		text = "Spanish, German, French, Russian, Portuguese, Italian, Korean and Chinese, with a " ..
		"Language choice on the main page." },
	{ date = "2026-10-14", page = "Swing timer", client = "forever", title = "Swing timer",
		text = "The game's swing timer fades between fights, with a ranged bar on top." },
	{ date = "2026-10-13", page = "Tooltips", title = "Tooltips page",
		text = "Hide tooltips in combat or in CineMode, with a key to hold that shows them anyway." },
	{ date = "2026-10-12", page = "Advanced Frames", title = "Plater support",
		text = "Plater's nameplates fade in CineMode like the game's own." },
	{ date = "2026-10-12", page = "Advanced Frames", title = "Add mode and Bartender4",
		text = "Add any addon's frame by clicking it, and Bartender4's bars fade too." },
	{ date = "2026-10-12", page = "Cooldown Manager", title = "Cooldown Manager page",
		text = "The game's Cooldown Manager fades in CineMode, with an Immersive (CDM) profile." },
	{ date = "2026-10-12", page = "Profiles", title = "Profiles",
		text = "Built-in profiles to start from, picked in a welcome window, and as many of your own as you like." },
	{ date = "2026-10-12", page = "Camera Triggers", title = "Stand still camera",
		text = "Standing still for a while can start a camera, like a screensaver." },
	{ date = "2026-10-12", page = "Mouseover groups", title = "Mouseover groups",
		text = "Frames that come up together when you mouse over any of them." },
	{ date = "2026-10-11", page = "Fishing", title = "Fishing",
		text = "A fishing camera and settings of its own." },
	{ date = "2026-10-11", page = "Gamepad", client = "forever", title = "Gamepad mode",
		text = "WoW Forever's gamepad mode fades with the rest, with a page of its own." },
	{ date = "2026-10-10", page = "Advanced Frames", title = "EllesmereUI support",
		text = "EllesmereUI's frames fade in CineMode." },
	{ date = "2026-10-10", page = "Quest tracker", title = "Quest tracker page",
		text = "The quest tracker and quest timer fade, and come up when you accept a quest." },
	{ date = "2026-10-09", page = "Advanced Frames", title = "Details! and Cooldown Manager Centered",
		text = "Both fade with the rest of the UI in CineMode." },
	{ date = "2026-10-08", page = "Camera Modes", title = "Tele Cam",
		text = "Hearthstones and teleports get a camera move of their own." },
	{ date = "2026-10-08", page = "Camera Modes", title = "Flight camera",
		text = "Flights get a cinematic camera, with a fly-by and an arrival shot." },
	{ date = "2026-10-08", title = "Retail too",
		text = "One Cinematic for WoW Forever and retail." },
	{ date = "2026-10-08", page = "Camera Modes", title = "Quest cam",
		text = "Talking to a quest giver brings the camera in close, drifting gently once settled." },
	{ date = "2026-10-06", page = "CineMode", title = "Cinematic",
		text = "The UI fades and letterbox bars come in between fights. Combat, casting and opening " ..
		"windows bring it back." },
}
