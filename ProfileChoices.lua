-- Profile choices: what players pick, and what each pick is made of. The
-- one file to change to shape the experience; the settings themselves are
-- in modules (ProfileModules.lua), and the welcome window, the Profiles
-- page and the dev build's Module Editor all read from here.
--
-- Three layers, each built from the one below:
--   Modules (ProfileModules.lua): a set of settings for the pages, or
--     sections of pages, it names.
--   Choices (ns.SLOT_CHOICES, here): each slot (an area of your setup:
--     the interface, action bars, camera...) has a few choices, and a
--     choice is a list of modules. Picking one swaps the slot's settings
--     for the choice's and leaves the rest as they are (ns.ApplyPart).
--   Profiles (ns.BUILTIN_PROFILES, here): a pick per slot (picks), on top
--     of the profile it's from (from), plus any modules of its own
--     (modules). A slot it doesn't pick has its default choice.
-- The welcome window's levels (ns.WELCOME_LEVELS, here) each pick a profile.
--
-- To change what a choice does, change its modules. To add one, add it to
-- its slot's choices (with hidden = true it's only for profiles, not offered
-- to players). To add a slot, add it to ns.PROFILE_SLOTS and ns.SLOT_CHOICES.
-- The dev build's Module Editor does all of this in the game and gives the
-- Lua to paste back here. lua5.1 Tools/offline/check.lua (and /cine debug
-- modules) checks that it all fits together.

local _, ns = ...
local L = ns.L

-- The slots, in the order a profile's choices go on (a later one's
-- modules after the earlier's).
ns.PROFILE_SLOTS = {
	{ key = "layout", name = "Edit Mode layout" },
	{ key = "frames", name = "UI manager" },
	{ key = "bars", name = "Action bars" },
	{ key = "camera", name = "Camera" },
	{ key = "vfx", name = "Visual effects" },
	{ key = "chat", name = "Chat" },
	{ key = "sound", name = "Sound" },
}

-- Each slot as players see it: its name (label), the options page with its
-- settings, a question, its default (the choice a profile that picks none
-- has; or { forever = part, retail = part }: ns.SlotDefault), and its choices. A choice: part (its key, what profiles pick it
-- by), label and line (what players read), client (only there),
-- hidden (only for profiles, not offered; a client's name: not offered
-- there), noCDM (made for the Cooldown Manager: not offered without one,
-- and a profile's pick of it is this choice there instead), made (a layout Cinematic makes
-- and adds to Edit Mode for you, tagged so in Customize), and modules (each a module's key,
-- or { forever = key, retail = key }).
ns.SLOT_CHOICES = {
	layout = { label = "Layout", page = "Profiles", question = "Where should your bars and menus sit?",
		default = "own", choices = {
		-- (Cinematic's own layouts first, then the player's and the game's)
		{ part = "retail", client = "forever", label = "Retail Inspired", made = true,
			line = "Action bars centered along the bottom, menus in the corner", modules = { "layout-retail" } },
		{ part = "pure", label = "Personal Resource Centered", made = true,
			line = "Your resources in the middle, the Cooldown Manager above", modules = { "layout-pure" } },
		{ part = "own", label = "Your own", line = "Cinematic leaves your Edit Mode layout as it is",
			modules = {} },
		{ part = "preset", client = "forever", label = ns.isClassicEra and "Classic's" or "WoW Forever's",
			line = "The game's own layout", modules = { "layout-preset" } },
	} },
	frames = { label = "Interface", page = "Standard Frames", question = "When does your UI fade?",
		default = "standard", choices = {
		-- (From the most fading to the least.)
		{ part = "pure", label = "Almost always", line = "As little UI as possible, even in fights",
			modules = { "pure-frames", "pure-minimap", "minimal-target", "pure-plates", "ultra-plates", "pure-tooltips" } },
		{ part = "immersive", label = "Most of the time",
			line = "Between fights, and fights bring back less: no minimap, fewer group nameplates",
			modules = { "recovering", "minimap-off-in-fights", "fewer-group-plates" } },
		{ part = "standard", label = "Between fights", line = "Fights and opening windows bring your UI back",
			modules = { "recovering" } },
		{ part = "solo", label = "Only when solo", line = "Out in the world on your own; normal in groups",
			modules = { "recovering", "solo-only" } },
		{ part = "nofade", label = "Never", line = "Your UI stays as the game has it, unless a camera brings CineMode on",
			modules = { "recovering", "no-fading" } },
	} },
	-- (Each client's own groups to start with: Forever's Classic group, retail's split.)
	bars = { label = "Action bars", page = "Mouseover groups", question = "When do your action bars show?",
		default = { forever = "grouped", retail = "standard" }, choices = {
		{ part = "always", label = "Always show", line = "Your action bars stay up all through CineMode",
			modules = { "bars-always" } },
		{ part = "grouped", label = "Action bars (Classic group)",
			line = "Point at one and the bars, menus and XP bar come up", modules = {} },
		-- (Retail Group: on retail the client's own, standard, which is the
		-- default there; on Forever, whose own is Classic Group, split.)
		{ part = "split", hidden = "retail", label = "Action bars (Retail group)",
			line = "Point at the bars, the menus or the XP bar; fights bring up just the bars",
			modules = { "retail-groups", "micro-off-in-fights" } },
		{ part = "standard", client = "retail", label = "Action bars (Retail group)",
			line = "Point at the bars, the menus or the XP bar", modules = { { retail = "retail-groups" } } },
		{ part = "pure", noCDM = "grouped", label = "Cooldown Manager",
			line = "In fights just the Cooldown Manager: no bars or menus",
			modules = { { retail = "retail-groups" }, "pure-cdm" } },
	} },
	camera = { label = "Camera", page = "Cameras", question = "When does the camera move on its own?",
		default = "standard", choices = {
		{ part = "pure", label = "All the time", line = "Every camera, standing still too, and none waits after a fight",
			modules = { "pure-cameras", "still-afk", "camera-music" } },
		{ part = "immersive", label = "Often", line = "Flights, campfires, vistas, fishing, quests, going AFK and more",
			modules = { "walk-run-music" } },
		{ part = "lite", label = "Sometimes", line = "Flights, going AFK, and your Hearthstone and teleports",
			modules = { "lite-cameras" } },
		{ part = "off", label = "Never", line = "The camera is all yours", modules = { "no-cameras" } },
		-- (Only Subtle's: not offered.)
		{ part = "travel", hidden = true, label = "Flights, teleports and AFK",
			line = "Flights, going AFK, and your Hearthstone and teleports, each in CineMode",
			modules = { "lite-cameras", "travel-cinemode" } },
		-- (Only the plain defaults': not offered.)
		{ part = "standard", hidden = true, label = "Every camera", line = "Every camera, as the defaults have them",
			modules = {} },
	} },
	vfx = { label = "Look", page = "Effects", question = "How should the world look?", default = "standard", choices = {
		{ part = "standard", label = "Letterbox and tint", line = "Bars top and bottom, a color tint, vignette and weather",
			modules = {} },
		{ part = "noletterbox", label = "Tint only", line = "The tint, vignette and weather, no letterbox",
			modules = { "no-letterbox" } },
		{ part = "cameras", label = "During cameras", line = "The effects only while a camera mode runs",
			modules = { "effects-in-cameras" } },
		-- (Only Subtle's: not offered.)
		{ part = "cinebars", hidden = true, label = "In CineMode",
			line = "The letterbox, tint, vignette and weather only in CineMode",
			modules = { "letterbox-in-cinemode", "tint-in-cinemode", "effects-in-cinemode" } },
		{ part = "pure", label = "Through fights", line = "Fights don't bring the letterbox down",
			modules = { "letterbox-in-fights" } },
	} },
	-- (From the most chatter to the least. Public channels don't bring chat
	-- up unless a choice turns them on: chatPeekChannels is off.)
	chat = { label = "Chat", page = "Chat", question = "How much chatter?", default = "standard", choices = {
		{ part = "lite", label = "General and Trade too", line = "NPC speech, and the General and Trade channels",
			modules = { "lite-channels" } },
		{ part = "standard", label = "NPC speech", line = "NPC speech brings chat up; public channels don't",
			modules = {} },
		{ part = "quietnpcs", label = "No NPC chatter", line = "Neither NPC speech nor public channels bring chat up",
			modules = { "no-npc-chat" } },
		{ part = "pure", label = "Quietest",
			line = "No NPC chatter; speech from behind you shows low on the screen",
			modules = { "no-npc-chat", "pure-chat" } },
	} },
	sound = { label = "Sound", page = "Audio", question = "How much music?", default = "standard", choices = {
		{ part = "standard", label = "Music on cameras", line = "A camera can bring music in, as the defaults have it",
			modules = {} },
		{ part = "spaced", label = "Spaced out", line = "Music on cameras, with half a minute between starts",
			modules = { "music-fatigue" } },
		{ part = "nomusic", label = "No music", line = "No music in CineMode", modules = { "no-cinemode-music" } },
	} },
}

-- The built-in profiles, in the order they're listed. picks: the choice
-- per slot (a choice's part, or { forever = part, retail = part } where it
-- differs by client; a slot not picked: the one it's from picks, else the
-- slot's default). from: the built-in it starts from. modules: any of its
-- own on top ("-key" takes one of the choices' out). client: only on that
-- one ("forever" or "retail"). label: the name shown, when it isn't the
-- saved name (two clients' profiles can't share a name in this list).
-- oldNames: what it was called before: settings and picks saved under
-- those move to it at login. dev: only in the dev build (one being made).
-- hidden: in no list, the dev build's too (only the Module Editor shows it).
-- preview: the mouseover group (its preset) shown for a moment when it's
-- picked on the Profiles page, the rest faded (ns.PreviewProfile).
-- default: the one a new player's settings start from until they pick one,
-- and that deleting your own goes back to (else the first).
-- (The modules every built-in has: the quiet extras that only show for a
-- moment. Each profile's own come after.)
local EVERY_PROFILE = { "milestone-cards", "duel-card", "tele-vision", "emote-vision" }
local function With(...)
	local list = {}
	for _, key in ipairs(EVERY_PROFILE) do list[#list + 1] = key end
	for _, key in ipairs({ ... }) do list[#list + 1] = key end
	return list
end

ns.BUILTIN_PROFILES = {
	-- The welcome window's three levels, the same on both clients.
	{
		name = "Subtle",
		label = "Subtle", -- (shown in your language)
		oldNames = { "VFX Only" },
		icon = "Interface\\Icons\\Spell_Nature_Lightning",
		tip = L["A light touch. Your UI stays as it is while you play, and fades only when you're just along for " ..
			"the ride: on flights, as you hearth or teleport, and when you go AFK. That's when the camera sweeps " ..
			"along and the letterbox, color tint, vignette and weather come in. A portal opens as you hearth, and " ..
			"small cards mark your big moments, the places you reach, your duels and the players who buff or " ..
			"emote at you."],
		picks = { layout = { forever = "preset" }, frames = "nofade", camera = "travel", vfx = "cinebars",
			sound = "nomusic" },
		modules = With("zone-card", "travel-cards", "no-visions", "no-custom-bubbles"),
	},
	{
		name = "Balanced",
		label = "Balanced", -- (shown in your language)
		oldNames = { "Lite" },
		default = true,
		icon = "Interface\\Icons\\Spell_Holy_HolyBolt",
		tip = L["The best of both. Your UI fades away and comes right back for a fight, a quest or a look " ..
			"with the mouse, with your bars and frames where you know them. The letterbox, tint and weather " ..
			"bring the world to life, most of the Visions and cards join in, and the camera takes over on " ..
			"flights, when you go AFK and for your Hearthstone and teleports."],
		picks = { layout = { forever = "preset" }, camera = "lite", chat = "lite" },
		modules = With("zone-card", "travel-cards", "damage-vision", "music-calm", "node-icons"),
		preview = "bars",
	},
	{
		name = "Cinema",
		label = "Cinema", -- (shown in your language)
		oldNames = { "Pure Cinema", "Full" }, -- (Full: on main for a day, not released)
		icon = "Interface\\Icons\\Ability_Stealth",
		tip = L["The full experience, with as little UI as possible, even in fights. Nameplates tell you what " ..
			"you need to know, the Cooldown Manager takes the place of your action bars, and your health " ..
			"shows at the screen's edges. Every camera, every Vision and all the atmosphere: the letterbox " ..
			"stays up through fights, and the camera comes alive on flights, by campfires, at vistas and " ..
			"more."],
		-- (On Forever, the Retail Inspired layout and its Retail group bars.)
		picks = { layout = { forever = "retail", retail = "pure" }, frames = "pure",
			bars = { forever = "split", retail = "pure" }, camera = "pure", vfx = "pure", chat = "pure" },
		-- (Its own Visions and cards, apart from the slots' choices: picking a
		-- choice for a slot then leaves them as they are.)
		modules = With("zone-card", "travel-cards", "story-cards", "damage-vision", "vitals-vision",
			"combat-vision", "heal-vision-everywhere", "cursor-hide", "music-calm", "weather-view-distance",
			"node-icons"),
	},
}

-- Names of built-ins Cinematic used to have, for what a player still has under
-- one (ns.InitProfiles): label, what it's kept as if you're on it; drop: never
-- kept. Just their names: the three above are all the built-ins there are.
ns.OLD_PROFILES = {
	{ name = "Forever Default", label = "Default", drop = true },
	{ name = "Forever CDM", label = "CDM", drop = true },
	{ name = "Forever Retail", label = "Retail", drop = true },
	{ name = "Retail Default", label = "Default" },
	{ name = "Retail CDM", label = "CDM" },
	{ name = "Retail Forever", label = "Forever" },
	{ name = "Camera Only" },
	{ name = "Solo Explorer" },
}

-- The welcome window's levels (Welcome.lua), and the profile each picks,
-- each with its own short line; the longer tip is its profile's (below).
ns.WELCOME_LEVELS = {
	{ label = "Subtle", profile = "Subtle", line = "A light touch. Your UI fades only when you're along for the ride." },
	{ label = "Balanced", profile = "Balanced", line = "Your UI fades away, and comes back when you need it." },
	-- (flash: something shown for a moment when it's picked, besides the
	-- profile's preview: "vitals", Vitals Vision's screen edges.)
	{ label = "Cinema", profile = "Cinema", flash = "vitals", line = "Full immersion: just you and the world." },
}

-- Each level's tip: its profile's, in English until both are translated.
do
	local tips = {}
	for _, profile in ipairs(ns.BUILTIN_PROFILES) do tips[profile.name] = profile.tip end
	for _, level in ipairs(ns.WELCOME_LEVELS) do level.tip = tips[level.profile] end
end

-- In your language once it's set (Locales.lua): the levels' text, and each
-- slot's name, question and choices.
ns.OnLanguage(function()
	ns.TranslateFields(ns.WELCOME_LEVELS, "label", "line", "tip")
	for _, info in pairs(ns.SLOT_CHOICES) do
		ns.TranslateFields({ info }, "label", "question")
		ns.TranslateFields(info.choices, "label", "line")
	end
end)
