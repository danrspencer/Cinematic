-- Cinematic: the dev build's Demo Hub (/cine demo). Every demo tool in one
-- place, for recording the showcase videos (Tools/video/playbook.md): the
-- test commands and pages scattered round the addon, and demo scripts that
-- run a shot on their own (a camera, a tint carousel, a settings tour...), so
-- a clip is: start recording, press Run, stop recording.
--
-- A script is a function run as a coroutine with a director, d, that it
-- calls to wait and act: d.Wait(seconds), d.WaitUntil(test, timeout),
-- d.Cam(camera section, seconds), d.Emote(token), d.Slash("tinttest 6"),
-- d.Cine(on), d.HideUI(hidden), d.Tint(preset), d.Set(key, value),
-- d.SetIn(table key, key, value), d.Animate(seconds, f), d.Caption(text),
-- d.Cue(text). Whatever it changes is put back as it ends, stopped or not,
-- and settings it changed are also put back after a /reload mid-demo
-- (db.debugDemoRestore). A tool is a plain function, run and done.
--
-- Settings: db.debugDemoHub (countdown, lead-in, hide the hub while running, captions,
-- seconds per settings page). Keys starting "debug" stay out of profiles.
-- The same list is the Dev hub's Demo Commands page. Dev copy only
-- (CinematicDev.toc; ignored in .pkgmeta).
local _, ns = ...

if not ns.isDev then
	return
end

local GOLD, SOFT, DIM = { 1, 0.82, 0 }, { 0.9, 0.9, 0.9 }, { 0.6, 0.6, 0.6 }
local HUB_W, HUB_H = 470, 600
local ROW_H, HEAD_H = 26, 30

local DEFAULT_SETTINGS = { countdown = 3, leadIn = 2, hideHub = true, captions = false, pageSeconds = 4 }
local function Settings()
	local db = ns.db
	if not db then return DEFAULT_SETTINGS end
	db.debugDemoHub = db.debugDemoHub or {}
	local s = db.debugDemoHub
	for key, value in pairs(DEFAULT_SETTINGS) do
		if s[key] == nil then s[key] = value end
	end
	return s
end

-- ---------------------------------------------------------------------------
-- The demos
-- ---------------------------------------------------------------------------

-- Groups in order: the shot list's recording sessions, then the rest.
local GROUPS = {
	"Sections", "Recording helpers", "1. Settings & menus", "2. Town & inn", "3. Flight & hearth", "4. Questing & combat",
	"5. Scenery & mood", "6. Group", "Dev pages & test commands",
}
local demos, byKey = {}, {}

-- def: key, name, tip, and script (function(d)) or run (function); still:
-- moving stops it (cameras end on moving anyway); client: "retail" or
-- "classic" if only there; needs: a function giving false and why when it
-- can't run here.
local function Add(group, def)
	def.group = group
	demos[#demos + 1] = def
	byKey[def.key] = def
end

-- Emotes, as Camera.lua does them (its hooks see these, so the cozy and vista
-- cameras start as if typed).
local function PerformEmote(token)
	if C_ChatInfo and C_ChatInfo.PerformEmote then
		pcall(C_ChatInfo.PerformEmote, token)
	elseif DoEmote then
		pcall(DoEmote, token)
	end
end

local function CloseSettings()
	if SettingsPanel and SettingsPanel:IsShown() and not InCombatLockdown() then
		HideUIPanel(SettingsPanel)
	elseif InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() and not InCombatLockdown() then
		HideUIPanel(InterfaceOptionsFrame)
	end
end

-- Sections: one recording each, the demos that run where you stand in a row
-- (Tools/video/playbook.md's sections). Captions (above) name each one.

local REELS = {
	{ "reel-look", "Reel: the look", "Tints, zone moods, vignette, depth of field, letterbox, the time of day, " ..
		"golden hour and moonlight B-roll, the Vista Cam (about 6 minutes). Somewhere pretty; stand still.",
		{ { "tints" }, { "moods" }, { "vignette" }, { "dof" }, { "letterbox" }, { "day" }, { "golden" }, { "night" },
			{ "stare" } } },
	{ "reel-visions", "Reel: visions and cards", "Tele Vision, Vitals Vision (a fall, then a minute of themes), " ..
		"every card, Damage Vision where it's loaded (about 5 minutes). Anywhere; stand still.",
		{ { "tele-vision", 10 }, { "vitals", 14 }, { "vitals-themes" }, { "cards" }, { "damage", 27 } } },
}
for _, reel in ipairs(REELS) do
	Add("Sections", { key = reel[1], name = reel[2], tip = reel[3], still = true,
		script = function(d)
			-- (CineMode and the UI hidden for the whole reel: each part putting
			-- its own back would flash the UI between them)
			d.Cine(true)
			d.HideUI(true)
			for _, part in ipairs(reel[4]) do d.Play(part[1], part[2]) end
		end })
end

-- Recording helpers -----------------------------------------------------------

Add("Recording helpers", { key = "clean", name = "Clean slate",
	tip = "Between takes: stops any camera test, tint sweep or depth of field demo, brings the UI back if " ..
		"it was hidden, turns CineMode on and swings the camera behind you.",
	run = function()
		if ns.CameraTestStop then ns.CameraTestStop() end
		if ns.DaySweep then ns.DaySweep() end
		if ns.StopLowHealthTest then ns.StopLowHealthTest() end
		if not UIParent:IsShown() then ns.ToggleUI() end
		CloseSettings()
		if ns.ProfileChosen() and not ns.db.enabled then ns.SetEnabled(true) end
		ns.HandleSlash("behind")
	end })
Add("Recording helpers", { key = "hideui", name = "Hide UI, keep the look",
	tip = "/cine hideui: the UI goes, the tint, letterbox and titles stay. Again to bring it back.",
	run = function() ns.ToggleUI() end })
Add("Recording helpers", { key = "cine", name = "CineMode on or off", tip = "/cine",
	run = function() Cinematic_Toggle() end })
Add("Recording helpers", { key = "letterbox", name = "Letterbox sweep",
	tip = "The bars close in to 12% of the screen, hold, and ease back to your size.",
	script = function(d)
		d.Cine(true)
		local start = ns.db.letterboxSize or 0.03
		d.Set("letterboxSize", start)
		local function Size(value) ns.db.letterboxSize = value ns.RefreshLetterbox() end
		d.Wait(2)
		d.Animate(2.5, function(t) Size(start + (0.12 - start) * t) end)
		d.Wait(3)
		d.Animate(2.5, function(t) Size(0.12 + (start - 0.12) * t) end)
		d.Wait(1)
	end })

-- 1. Settings & menus -----------------------------------------------------------

-- Each hub's pages (English names, as ns.OpenOptions takes them). Pages a
-- client hasn't got are skipped.
-- (The pages' ids, as in Options.lua's HUBS: some show other names, e.g.
-- Standard Frames is Game Frames.)
local TOURS = {
	{ "tour-main", "Main page and Profiles", { "", "Profiles" } },
	{ "tour-ui", "Interface", { "Standard Frames", "Advanced Frames", "Mouseover groups", "Gamepad", "Unit Frames",
		"Personal Resources", "Buffs/debuffs", "Cooldown Manager", "Swing timer", "Minimap", "Quest tracker",
		"Tooltips", "Chat", "Nameplates", "Chat bubbles" } },
	{ "tour-style", "Style", { "Style General", "Unit Style", "Raid Style", "Action Style", "Personal Style", "Tooltip Style",
		"Nameplate Style", "Name Style", "Cast Bar Style", "Bubble Style" } },
	{ "tour-camera", "Camera", { "Cameras", "Scenes", "Camera Scripts", "My Shots" } },
	{ "tour-look", "Atmosphere", { "Effects", "Tint", "Tint Style", "Letterbox", "Letterbox Style", "Graphics+",
		"Audio" } },
	{ "tour-visions", "Visions", { "Heal Vision", "Vitals Vision", "Vitals Style", "Quest Vision",
		"Quest Talk Style", "Quest Item Style", "Roll Vision", "Roll Style", "Duel Vision", "Card Vision",
		"Card Styles", "Card Style", "Card Sounds" } },
	{ "tour-wheels", "Wheels", { "Master wheel", "Your wheels", "Camera wheel", "Menu wheel", "Marker wheel",
		"Ground marker wheel", "Vision wheel" } },
	{ "tour-more", "Quality of life, Keybinds, Community", { "General", "Fishing", "Hunter", "Keybinds",
		"New features", "All changes", "Socials", "Help", "Why showing" } },
}
local function TourPages(pages)
	local list = {}
	for _, page in ipairs(pages) do
		if page == "" or not ns.HasOptionsPage or ns.HasOptionsPage(page) then list[#list + 1] = page end
	end
	return list
end
local function Tour(d, pages)
	for _, page in ipairs(TourPages(pages)) do
		d.Cue("page: " .. (page == "" and "main" or page))
		ns.OpenOptions(page ~= "" and page or nil)
		d.Wait(Settings().pageSeconds)
	end
end
local everyPage = {}
for _, tour in ipairs(TOURS) do
	for _, page in ipairs(tour[3]) do everyPage[#everyPage + 1] = page end
end
Add("1. Settings & menus", { key = "tour-all", name = "Settings tour: every page",
	tip = "Opens every settings page in turn, the hub's seconds-per-page each (Pages button above). " ..
		"Raise WoW's UI Scale first so the text reads well.",
	script = function(d) Tour(d, everyPage) end })
for _, tour in ipairs(TOURS) do
	Add("1. Settings & menus", { key = tour[1], name = "Settings tour: " .. tour[2],
		tip = "Opens each page in turn: " .. table.concat(tour[3], ", "):gsub("^, ", "main page, "),
		script = function(d) Tour(d, tour[3]) end })
end
Add("1. Settings & menus", { key = "menu-look", name = "Menu look: HD, then SD",
	tip = "Opens the Tint page (sliders, dropdowns, buttons and boxes: the most to see change) and flips " ..
		"Cinematic's windows between the flat HD look and the game's own SD look, twice. Your Menu look is " ..
		"put back.",
	script = function(d)
		local was = CinematicDB.menuSkin -- (the account's, not ns.db: Remember can't keep it over a reload)
		d.Restore(function()
			CinematicDB.menuSkin = was
			ns.ApplyMenuSkin()
		end)
		ns.OpenOptions("Tint")
		d.Wait(1.5)
		for _ = 1, 2 do
			for _, skin in ipairs({ "HD", "SD" }) do
				CinematicDB.menuSkin = skin
				ns.ApplyMenuSkin()
				d.Caption(skin, 3)
				d.Wait(3)
			end
		end
	end })
Add("1. Settings & menus", { key = "why", name = "Inspect: why is it showing?",
	tip = "/cine why: then click a frame and Inspect says what keeps it up. Again to stop.",
	run = function() ns.HandleSlash("why") end })
Add("1. Settings & menus", { key = "welcome", name = "Welcome window", tip = "/cine welcome",
	run = function() ns.ShowWelcome() end })
Add("1. Settings & menus", { key = "welcome-tour", name = "Welcome window: Subtle, Balanced, Cinema",
	tip = "Opens the welcome window and picks each level in turn (the mouse over it, then a click), 3 seconds " ..
		"each and 5 on Cinema, the UI changing with it. Your profile is put back after.",
	needs = function() return ns.WelcomeCards ~= nil, "The welcome window isn't loaded" end,
	script = function(d)
		local was = ns.ActiveProfile()
		d.Cine(ns.db.enabled and true or false)
		d.Restore(function() if ns.ActiveProfile() ~= was then ns.SetProfile(was) end end)
		ns.ShowWelcome()
		d.Wait(2)
		local cards = ns.WelcomeCards()
		for i, card in ipairs(cards) do
			if cards[i - 1] then cards[i - 1]:GetScript("OnLeave")(cards[i - 1]) end
			card:GetScript("OnEnter")(card)
			d.Wait(0.8)
			d.Cue("picked " .. i)
			card:Click()
			d.Wait(i == #cards and 5 or 3)
		end
	end })
Add("1. Settings & menus", { key = "export", name = "Share: export the profile",
	tip = "/cine export (a built-in profile says to make your own first)", run = function() ns.HandleSlash("export") end })
Add("1. Settings & menus", { key = "import", name = "Share: import a profile", tip = "/cine import",
	run = function() ns.HandleSlash("import") end })
Add("1. Settings & menus", { key = "whatsnew", name = "What's new page",
	run = function() ns.OpenOptions("New features") end })
Add("1. Settings & menus", { key = "log", name = "Bug report log", tip = "/cine log",
	run = function() ns.HandleSlash("log") end })

-- 2. Town & inn -----------------------------------------------------------------

Add("2. Town & inn", { key = "hook", name = "The hook: full UI, then CineMode",
	tip = "CineMode off (your full UI) for 4 seconds, then on: the UI fades and the letterbox slides in. " ..
		"Also the shot for the Other addons montage.",
	script = function(d)
		d.Cine(false)
		d.Wait(4)
		d.Cue("CineMode on")
		ns.SetEnabled(true)
		d.Wait(8)
	end })
Add("2. Town & inn", { key = "hook-back", name = "UI back and away again",
	tip = "CineMode on, then off for 4 seconds (the UI returns) and on again: the fade both ways.",
	script = function(d)
		d.Cine(true)
		d.Wait(3)
		ns.SetEnabled(false)
		d.Wait(4)
		ns.SetEnabled(true)
		d.Wait(6)
	end })
Add("2. Town & inn", { key = "hook-walk", name = "The hook: walk in, then CineMode",
	tip = "CineMode off (your full UI). Start auto-walking (walk mode + auto-run) toward the city: 6 seconds " ..
		"after you set off, CineMode comes on and the RP walk camera takes over as the UI fades.",
	script = function(d)
		d.Cine(false)
		d.Set("walkCameraDelay", 0)
		d.Caption("Walk mode, then auto-run", 4)
		if not d.WaitUntil(function() return ns.IsRPWalking and ns.IsRPWalking() end, 60) then return end
		d.Wait(6)
		d.Cue("CineMode on")
		ns.SetEnabled(true)
		d.Wait(25)
	end })
local CHAT_LINES = {
	{ "Aldric", "Anyone heading to Goldshire? Could use a hand with the kobolds." },
	{ "Mirelle", "Just watch out for the gnolls past the river." },
	{ "Aldric", "Thanks! See you at the Lion's Pride." },
}
Add("2. Town & inn", { key = "chat-peek", name = "Chat pops up",
	tip = "Three made-up /say lines arrive in your main chat window, a few seconds apart, and the chat comes " ..
		"up for each as a real one would. Only you see them.",
	script = function(d)
		d.Cine(true)
		d.Wait(2)
		local info = ChatTypeInfo and ChatTypeInfo.SAY
		for _, line in ipairs(CHAT_LINES) do
			local text = (CHAT_SAY_GET or "%s says: "):format("[" .. line[1] .. "]") .. line[2]
			DEFAULT_CHAT_FRAME:AddMessage(text, info and info.r or 1, info and info.g or 1, info and info.b or 1)
			if ns.PeekChat then ns.PeekChat(DEFAULT_CHAT_FRAME, 6) end
			d.Wait(4)
		end
		d.Wait(4)
	end })
local SPEECH_LINES = {
	{ "CHAT_MSG_MONSTER_SAY", "Town Crier", "Hear ye! The harvest festival begins at dusk!" },
	{ "CHAT_MSG_MONSTER_SAY", "Guard Thomas", "Keep your weapons sheathed inside the walls, traveler." },
	{ "CHAT_MSG_MONSTER_YELL", "Blacksmith Argus", "Fresh steel! Get it while the forge is hot!" },
}
Add("2. Town & inn", { key = "speech", name = "Speech from behind you",
	tip = "Three made-up NPC lines rise from the bottom of the screen, as speech from behind you does.",
	script = function(d)
		d.Cine(true)
		d.Wait(1.5)
		for _, line in ipairs(SPEECH_LINES) do
			ns.ShowSpeechBehind(line[1], line[2], line[3])
			d.Wait(4.5)
		end
		d.Wait(3)
	end })
Add("2. Town & inn", { key = "attack", name = "\"Under attack!\" warning", tip = "/cine attacktest",
	run = function() ns.HandleSlash("attacktest") end })
Add("2. Town & inn", { key = "update-notice", name = "Update notice in chat",
	tip = "The chat line shown at login after an update, with its What's new link.",
	run = function() ns.ShowUpdateNotice(3) end })
Add("2. Town & inn", { key = "dance", name = "Cozy Cam: /dance", still = true,
	script = function(d)
		d.Cine(true)
		PerformEmote("DANCE")
		d.Restore(function() PerformEmote("STAND") end)
		d.Wait(15)
	end })

-- Cameras that have a Test (CameraTests.lua): each runs where you stand.
local CAMERAS = {
	{ "Quest Cam", "2. Town & inn", 20, "as if talking to a quest giver" },
	{ "RP Walk Cam", "2. Town & inn", 25, "as if auto-walking" },
	{ "Flight Cam", "3. Flight & hearth", 30, "as if on a flight path: no route known, so it doesn't land" },
	{ "Tele Cam", "3. Flight & hearth", 15, "the Hearthstone's cast pretended" },
	{ "Death Cam", "4. Questing & combat", 30, "you lie down as if dead" },
	{ "AFK Cam", "5. Scenery & mood", 30, "the slow sweep around you" },
	{ "Cozy Cam", "5. Scenery & mood", 20, "as if sitting" },
	{ "Vista Cam", "5. Scenery & mood", 20, "as if /stare-ing at the view" },
	{ "Fish Cam", "5. Scenery & mood", 15, "as if fishing" },
	{ "Auto-run Cam", "5. Scenery & mood", 25, "as if auto-running" },
}
for _, cam in ipairs(CAMERAS) do
	local section, group, seconds, what = cam[1], cam[2], cam[3], cam[4]
	Add(group, { key = "cam-" .. section:lower():gsub(" cam$", ""):gsub("[^%a]", ""), name = section, still = true,
		tip = ("Runs the %s for %d seconds where you stand, %s. Stand still: moving ends it."):format(
			section, seconds, what),
		script = function(d)
			d.Cine(true)
			d.Wait(0.5)
			d.Cam(section, seconds)
		end })
end

-- 3. Flight & hearth ------------------------------------------------------------

Add("3. Flight & hearth", { key = "tele-vision", name = "Tele Vision: a pretend Hearthstone",
	tip = "Tele Vision's Test: the portal opens around you as if casting your Hearthstone, then the screen " ..
		"goes black. Again stops it.",
	needs = function() return ns.TestTeleportVision ~= nil, "Tele Vision isn't loaded" end,
	run = function() ns.TestTeleportVision() end })
Add("3. Flight & hearth", { key = "tele-colors", name = "Tele Vision: every class color",
	tip = "/cine teleport colors: a pretend cast in each class and spec's color, 4 seconds each, numbered. " ..
		"Again stops it.",
	needs = function() return ns.TeleportColorReel ~= nil, "Tele Vision isn't loaded" end,
	run = function() ns.HandleSlash("teleport colors") end })
Add("3. Flight & hearth", { key = "flight-director", name = "Flight director",
	tip = "Start it, then take a flight: a fly-by 12 seconds after takeoff and every 25 seconds after, " ..
		"until you land. Waits up to 10 minutes for the flight.",
	script = function(d)
		d.Cine(true)
		d.Cue("waiting for a flight")
		if not d.WaitUntil(ns.OnTaxi, 600) then return end
		d.Cue("took off")
		d.Wait(12)
		while ns.OnTaxi() do
			if not ns.FlyByTurning() then
				local ok = ns.ToggleFlyBy()
				if ok then d.Cue("fly-by") end
			end
			d.WaitUntil(function() return not ns.OnTaxi() end, 25)
		end
		d.Cue("landed")
		d.Wait(4)
	end })

-- 4. Questing & combat ----------------------------------------------------------

Add("4. Questing & combat", { key = "vitals", name = "Vitals Vision: one fall",
	tip = "The Vitals Vision page's Test: health falls as its Test section says, then comes back.",
	run = function() ns.TestLowHealth() end })
Add("4. Questing & combat", { key = "vitals-3", name = "Vitals Vision: three falls",
	tip = "The Test three times with a pause between, for a choice of takes.",
	script = function(d)
		d.Restore(function() if ns.StopLowHealthTest then ns.StopLowHealthTest() end end)
		for _ = 1, 3 do
			ns.TestLowHealth()
			d.Wait((ns.db.lowHealthTestTime or 8) + 5)
		end
	end })
Add("4. Questing & combat", { key = "vitals-glimpse", name = "Vitals Vision: quick glimpse",
	tip = "The welcome window's short look: health drops in hits, holds 3 seconds, comes back.",
	run = function() ns.FlashVitals(3) end })

Add("4. Questing & combat", { key = "vitals-all", name = "Vitals Vision: every theme once",
	tip = "/cine vital demo all: every theme in the menu's order, numbered with its key, then stops.",
	run = function() ns.VitalsDemo({ "all" }) end })
Add("4. Questing & combat", { key = "vitals-themes", name = "Vitals Vision: theme reel",
	tip = "/cine vital demo 4: a random spec's theme every 4 seconds, its name on the screen, for a minute.",
	script = function(d)
		d.Restore(function() ns.VitalsDemo({ "off" }) end)
		ns.VitalsDemo({ "4" })
		d.Wait(60)
	end })

-- Cards (Cards.lua): each moment's made-up card, as the Card Vision page's Test.
local CARDS = {
	{ "combatIn", "Entering combat", "4. Questing & combat" },
	{ "combatOut", "Leaving combat", "4. Questing & combat" }, { "boss", "Boss", "4. Questing & combat" },
	{ "death", "Death", "4. Questing & combat" }, { "zone", "Zone name", "2. Town & inn" },
	{ "login", "Last time", "2. Town & inn" }, { "time", "Time of day", "5. Scenery & mood" },
	{ "attack", "Under attack", "2. Town & inn" }, { "duel", "Duel", "4. Questing & combat" },
	{ "cleared", "Dungeon cleared", "4. Questing & combat" }, { "subzone", "Subzone", "2. Town & inn" },
	{ "discover", "Discovered", "5. Scenery & mood" }, { "departure", "Flight departure", "5. Scenery & mood" },
	{ "arrival", "Flight arrival", "5. Scenery & mood" },
	{ "rested", "Rested", "2. Town & inn" }, { "levelUp", "Level up", "4. Questing & combat" },
	{ "achievement", "Achievement", "4. Questing & combat" }, { "reputation", "Reputation", "2. Town & inn" },
	{ "collect", "New mount or pet", "2. Town & inn" }, { "profession", "Profession rank", "2. Town & inn" },
	{ "quest", "Story quest", "4. Questing & combat" }, { "rare", "Rare spotted", "4. Questing & combat" },
	{ "battleground", "Battleground", "4. Questing & combat" }, { "streak", "Kill streak", "4. Questing & combat" },
}
for _, card in ipairs(CARDS) do
	if ns.CARD_BY_ID[card[1]] then -- (each this client has)
		Add(card[3], { key = "card-" .. card[1], name = "Card: " .. card[2],
			tip = "The " .. card[2] .. " card, made up, in its look on the Card Vision page.",
			run = function() ns.CardTest(card[1]) end })
	end
end
Add("4. Questing & combat", { key = "cards", name = "Cards carousel: every card",
	tip = "Every card this client has, in the page's order, 7 seconds each (a card with moments, all of them), UI " ..
		"hidden. Change the looks on Card Styles first to show yours.",
	script = function(d)
		d.Cine(true)
		d.HideUI(true)
		d.Wait(1)
		for _, event in ipairs(ns.CARD_EVENTS) do
			local id = event.id
			d.Cue("card " .. id)
			ns.CardTest(id)
			-- (A card with moments plays each in turn, its hold and 2 seconds apart.)
			local sequence = ns.CardSequences[id]
			local moments = sequence and #sequence() or 1
			d.Wait(moments > 1 and moments * ((tonumber(ns.CardLook(id).combatHoldIn) or 3) + 2) + 1 or 7)
		end
	end })
-- Card shots: each card (each moment of one with moments) on its own, a
-- screenshot of it once it's all in, the list of them saved
-- (CinematicDB.debugCardShots: the card and the shot's time, as the
-- screenshot's file name has it) to look over after a /reload.
local IN_TIME = { fade = 0.35, reveal = 1.1, track = 1.4 }
Add("4. Questing & combat", { key = "card-shots", name = "Card shots: a screenshot of every card",
	tip = "Every card this client has (each moment of a card with moments), one at a time with the UI hidden, a " ..
		"screenshot of each once it's all in. /reload after, so the list of which shot is which is saved.",
	needs = function() return Screenshot ~= nil, "no Screenshot on this client" end,
	script = function(d)
		d.Cine(true)
		d.HideUI(true)
		d.Wait(1)
		local list = {}
		ns.db.debugCardShots = list
		for _, event in ipairs(ns.CARD_EVENTS) do
			local id = event.id
			local sequence = ns.CardSequences[id]
			local cards = sequence and sequence() or { ns.CardSample(id) }
			for n, card in ipairs(cards) do
				local look = ns.CardLook(id)
				local name = type(card.name) == "string" and card.name or ""
				local into = look.combatAnim == "type" and #name * 0.07 or IN_TIME[look.combatAnim] or 0.35
				local hold = tonumber(look.combatHoldIn) or 3
				d.Cue(("card %s %d"):format(id, n))
				ns.Cards.Fire(id, card, true)
				d.Wait(into + 0.4 + math.min(0.6, hold * 0.5)) -- (the other lines risen in too)
				list[#list + 1] = { id = id, moment = n, name = name, at = date("%m%d%y_%H%M%S") }
				Screenshot()
				d.Wait(0.3)
				if ActionStatus then ActionStatus:Hide() end -- (its "Screen captured" off the next)
				d.Wait(hold + 1.5)
				ns.Cards.Cut(id)
				d.Wait(0.8)
			end
		end
		ns.Print(("Card shots: %d taken. /reload to save their list."):format(#list))
	end })
Add("4. Questing & combat", { key = "damage", name = "Damage Vision: made-up fight",
	tip = "Damage Vision's Test: a made-up 25-second race with four others, in the style picked on its page.",
	needs = function() return ns.TestDamageVision ~= nil, "Damage Vision isn't loaded" end,
	run = function() ns.TestDamageVision() end })
Add("4. Questing & combat", { key = "damage-recap", name = "Damage Vision: recap",
	tip = "The recap shown after a boss or dungeon (made up if the meter has nothing).",
	needs = function() return ns.TestDamageRecap ~= nil, "Damage Vision isn't loaded" end,
	run = function() ns.TestDamageRecap() end })
Add("2. Town & inn", { key = "recap", name = "Login with Last time",
	tip = "/cine recaptest: the zone name fades in as at login, with the Last time line (or its card).",
	run = function() ns.RecapDemo() end })

-- 5. Scenery & mood -------------------------------------------------------------

Add("5. Scenery & mood", { key = "day", name = "Time of day sweep",
	tip = "/cine tinttest 6: every time of day's tint and title, 6 seconds each, the AFK camera circling, " ..
		"with the UI hidden.",
	script = function(d)
		d.Cine(true)
		d.HideUI(true)
		d.Restore(function() ns.DaySweep() end)
		d.Slash("tinttest 6")
		d.Wait(7 * 6 + 2)
	end })
Add("5. Scenery & mood", { key = "titles", name = "Time-of-day titles", tip = "/cine timetest all",
	script = function(d)
		d.Slash("timetest all")
		d.Wait(7 * 8)
	end })
local PRESET_TOUR = { "none", "warm", "cool", "night", "dusk", "sepia", "dreamy" }
Add("5. Scenery & mood", { key = "tints", name = "Tint presets carousel",
	tip = "Same spot, UI hidden: no tint, then warm, cool, night, dusk, sepia and dreamy, 4 seconds each " ..
		"(captions name them if Captions is ticked). Your preset is put back.",
	script = function(d)
		d.Cine(true)
		d.HideUI(true)
		for _, key in ipairs(PRESET_TOUR) do
			d.Tint(key)
			d.Caption(ns.GetTintPresetLabel(key), 4)
			d.Wait(4)
		end
	end })
Add("5. Scenery & mood", { key = "moods", name = "Zone moods carousel",
	tip = "Every zone mood in turn on the zone you're in (snow, desert, swamp, fel...), 3.5 seconds each, " ..
		"UI hidden. Your zone's own setting is put back.",
	script = function(d)
		d.Cine(true)
		d.HideUI(true)
		d.Tint("zone")
		local zone = GetRealZoneText() or ""
		for _, mood in ipairs(ns.GetZoneMoods()) do
			d.SetIn("zoneTints", zone, mood.key)
			ns.RefreshTint()
			d.Caption(mood.label, 3.5)
			d.Wait(3.5)
		end
	end })
Add("5. Scenery & mood", { key = "golden", name = "B-roll: golden hour",
	tip = "UI hidden, the warm tint, and the AFK camera for 30 seconds.", still = true,
	script = function(d)
		d.Cine(true)
		d.HideUI(true)
		d.Tint("warm")
		d.Cam("AFK Cam", 30)
	end })
Add("5. Scenery & mood", { key = "night", name = "B-roll: moonlight",
	tip = "UI hidden, the night tint, and the AFK camera for 30 seconds.", still = true,
	script = function(d)
		d.Cine(true)
		d.HideUI(true)
		d.Tint("night")
		d.Cam("AFK Cam", 30)
	end })
Add("5. Scenery & mood", { key = "dof", name = "Depth of field: three strengths",
	tip = "The edge haze at 10%, 25% and 45%, 5 seconds each, with the UI hidden.",
	script = function(d)
		d.Cine(true)
		d.HideUI(true)
		for _, strength in ipairs({ 0.1, 0.25, 0.45 }) do
			ns.FocusDemo(5, strength)
			d.Caption(("Depth of field %d%%"):format(strength * 100), 5)
			d.Wait(5)
		end
		d.Wait(1)
	end })
Add("5. Scenery & mood", { key = "vignette", name = "Vignette sweep",
	tip = "The vignette eases up to 60%, holds, and eases back to yours.",
	script = function(d)
		d.Cine(true)
		d.Set("vignette", true)
		local start = ns.db.vignetteStrength or 0.1
		d.Set("vignetteStrength", start)
		local function Strength(value) ns.db.vignetteStrength = value ns.RefreshTint() end
		d.Wait(1.5)
		d.Animate(3, function(t) Strength(start + (0.6 - start) * t) end)
		d.Wait(2)
		d.Animate(3, function(t) Strength(0.6 + (start - 0.6) * t) end)
		d.Wait(1)
	end })
Add("5. Scenery & mood", { key = "cozy-tour", name = "Cozy Cam: sit, kneel, sleep, dance", still = true,
	tip = "Each emote for 12 seconds with a stand between, for the Cozy Cam's shots.",
	script = function(d)
		d.Cine(true)
		d.Restore(function() PerformEmote("STAND") end)
		for _, token in ipairs({ "SIT", "KNEEL", "SLEEP", "DANCE" }) do
			d.Cue("/" .. token:lower())
			PerformEmote(token)
			d.Wait(12)
			PerformEmote("STAND")
			d.Wait(3)
		end
	end })
Add("5. Scenery & mood", { key = "stare", name = "Vista Cam: /stare", still = true,
	tip = "The real emote, so the Vista Cam starts as it would for you.",
	script = function(d)
		d.Cine(true)
		PerformEmote("STARE")
		d.Wait(20)
	end })
Add("5. Scenery & mood", { key = "reel", name = "Camera reel: every camera", still = true,
	tip = "Every camera with a Test, one after another (about 3 minutes): AFK, Cozy, Vista, Fish, Tele, " ..
		"Quest, Flight, RP Walk, Auto-run, Death. Stand somewhere pretty and keep still.",
	script = function(d)
		d.Cine(true)
		for _, section in ipairs({ "AFK Cam", "Cozy Cam", "Vista Cam", "Fish Cam", "Tele Cam", "Quest Cam",
			"Flight Cam", "RP Walk Cam", "Auto-run Cam", "Death Cam" }) do
			d.Caption(section, 4)
			d.Cam(section, section == "Death Cam" and 25 or 15)
			d.Wait(3)
		end
	end })
Add("5. Scenery & mood", { key = "wheel", name = "Camera wheel",
	tip = "Opens the camera wheel at your cursor for 4 seconds, as holding its key does. Put the cursor " ..
		"in the middle first.",
	script = function(d)
		d.Restore(function() Cinematic_CameraWheel("up") end)
		d.Wait(0.5)
		Cinematic_CameraWheel("down")
		d.Wait(4)
		Cinematic_CameraWheel("up")
		d.Wait(1)
	end })

-- 6. Group ------------------------------------------------------------------------

Add("6. Group", { key = "rolls", name = "Roll Vision: made-up rolls", tip = "/cine rolls test",
	run = function() ns.HandleSlash("rolls test") end })
Add("6. Group", { key = "party", name = "Act as if in a party",
	tip = "/cine debug group party: the group options act as if you were grouped. Again with Act solo.",
	run = function() ns.HandleSlash("debug group party") end })
Add("6. Group", { key = "solo", name = "Act solo again", tip = "/cine debug group off",
	run = function() ns.HandleSlash("debug group off") end })
Add("6. Group", { key = "duels", name = "Duel Vision: pretend duels",
	tip = "/cine debug duels test: friendly players around you as if dueling each other (5 minutes, again " ..
		"stops). Somewhere busy, e.g. outside a city bank.",
	run = function() ns.HandleSlash("debug duels test") end })

-- Dev pages & test commands -----------------------------------------------------

local DEV_PAGES = {
	{ "grid", "Grid Demo page", "Grid Demo" }, { "profiles-demo", "Profiles Demo page", "Profiles Demo" },
	{ "modules", "Module Editor page", "Module Editor" }, { "wind-page", "Wind Guide page", "Wind Guide" },
	{ "cam-tests", "Camera Settings (each camera's Test)", "Camera Settings" },
	{ "shoulder", "Shoulder Cam page", "Shoulder Cam" }, { "held", "Held Game Settings page", "Held Game Settings" },
	{ "vitals-page", "Vitals Vision page (Test settings)", "Vitals Vision" },
}
for _, page in ipairs(DEV_PAGES) do
	Add("Dev pages & test commands", { key = page[1], name = page[2],
		needs = function()
			return not ns.HasOptionsPage or ns.HasOptionsPage(page[3]), "no such page on this client"
		end,
		run = function() ns.OpenOptions(page[3]) end })
end
local COMMANDS = {
	{ "doftest", "doftest", "Depth of field for 30 seconds (again stops)" },
	{ "deathtest", "deathtest", "Death camera, 30 seconds (again stops)" },
	{ "tinttest", "tinttest", "Every time of day, 8 seconds each (again stops)" },
	{ "speech-sample", "debug speech", "A sample line of speech from behind, and print each say (again stops)" },
	{ "whatsnew-line", "debug whatsnew", "The update notice's chat line" },
	{ "tent", "debug tent cozy", "As if a Camp Tent were moused over, and the cozy camera" },
	{ "starttest", "starttest gentle", "One slow camera move, to find what snaps" },
	{ "zoomtest", "zoomtest", "Camera zoom test" },
	{ "drifttest", "drifttest", "Camera drift test" },
	{ "pitchtest", "pitchtest", "Camera pitch test" },
	{ "songtest", "songtest", "A death song (again stops)" },
}
for _, command in ipairs(COMMANDS) do
	Add("Dev pages & test commands", { key = command[1], name = "/cine " .. command[2], tip = command[3],
		run = function() ns.HandleSlash(command[2]) end })
end
Add("Dev pages & test commands", { key = "wind", name = "Wind Guide test",
	needs = function() return ns.TestWindGuide ~= nil, "Wind Guide isn't loaded" end,
	run = function() ns.TestWindGuide() end })
Add("Dev pages & test commands", { key = "chatcam", name = "Chat Cam (prototype)", tip = "/cine chatcam",
	needs = function() return ns.ChatCamCommand ~= nil, "Chat Cam isn't loaded" end,
	run = function() ns.HandleSlash("chatcam") end })

-- ---------------------------------------------------------------------------
-- Settings put back after a /reload mid-demo
-- ---------------------------------------------------------------------------

local function Write(path, value)
	local db = ns.db
	if #path == 1 then
		db[path[1]] = value
	elseif type(db[path[1]]) == "table" then
		db[path[1]][path[2]] = value
	end
end
local function RefreshAll()
	if ns.RefreshTint then ns.RefreshTint() end
	if ns.RefreshLetterbox then ns.RefreshLetterbox() end
end
local function RestoreLeftovers()
	local saved = ns.db and ns.db.debugDemoRestore
	if not saved then return end
	for _, entry in pairs(saved) do
		Write(entry.path, entry.value)
	end
	ns.db.debugDemoRestore = nil
	RefreshAll()
	ns.Print("Demo Hub: put back the settings a demo had changed before the reload.")
end

-- ---------------------------------------------------------------------------
-- The director
-- ---------------------------------------------------------------------------

local overlay, countdownText, captionText -- (on the world frame: shown with the UI hidden too)
local function Overlay()
	if overlay then
		overlay:SetScale(UIParent:GetEffectiveScale() / WorldFrame:GetEffectiveScale())
		return overlay
	end
	overlay = CreateFrame("Frame", nil, WorldFrame)
	overlay:SetAllPoints(WorldFrame)
	overlay:SetFrameStrata("FULLSCREEN_DIALOG")
	local big = CreateFrame("Frame", nil, overlay)
	big:SetSize(200, 100)
	big:SetPoint("CENTER")
	big:SetScale(3)
	countdownText = big:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	countdownText:SetPoint("CENTER")
	local caption = CreateFrame("Frame", nil, overlay)
	caption:SetSize(600, 40)
	caption:SetScale(1.5)
	captionText = caption:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	captionText:SetPoint("CENTER")
	captionText:SetShadowOffset(2, -2)
	overlay.caption = caption
	local stop = CreateFrame("Frame", nil, overlay)
	stop:SetSize(260, 64)
	stop:SetPoint("CENTER")
	stop:SetScale(3)
	stop:Hide()
	local back = stop:CreateTexture(nil, "BACKGROUND")
	back:SetAllPoints()
	back:SetColorTexture(0, 0, 0, 0.8) -- (any scene: the words on a dark box)
	stop.text = stop:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	stop.text:SetPoint("CENTER", 0, 9)
	stop.text:SetTextColor(1, 0.3, 0.25)
	stop.text:SetText("Stop recording")
	stop.sub = stop:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	stop.sub:SetPoint("TOP", stop.text, "BOTTOM", 0, -4)
	overlay.stop = stop
	overlay:SetScale(UIParent:GetEffectiveScale() / WorldFrame:GetEffectiveScale())
	return overlay
end

local current -- the run going now
local driver = CreateFrame("Frame")
local hub, RefreshHub -- (the window, below)

-- As a script ends: every window closed (out of combat: closing some in a
-- fight is blocked) and "Stop recording" in the middle of the screen, so the
-- take ends on a clean frame. It stays till you move (after standing still:
-- moving may be what stopped it), the next demo starts, or STOP_MAX seconds;
-- then the hub comes back if it hid.
local STOP_MAX = 60
local stopping -- (while Stop recording is up: whether the hub waits to come back)
local function HideStopCue(showHub)
	local was = stopping
	if not was then return end
	stopping = nil
	overlay.stop:Hide()
	if showHub and was.hub and hub and not current then hub:Show() end
	return was.hub
end
local function StopCue(run, why)
	if not InCombatLockdown() then
		CloseSettings()
		if CloseAllWindows then pcall(CloseAllWindows) end
	end
	local stop = Overlay().stop
	stop.sub:SetText(run.demo.name .. " " .. (why or "done"))
	stopping = { hub = run.hidHub, at = GetTime() }
	ns.SetOnUpdate(stop, function()
		local now = stopping
		if not now then return end
		if not ns.playerMoving then now.still = true end
		if (now.still and ns.playerMoving) or GetTime() - now.at > STOP_MAX then HideStopCue(true) end
	end)
	stop:Show()
end

local function Finish(why)
	local run = current
	if not run then return end
	current = nil
	ns.SetOnUpdate(driver, nil)
	for i = #run.restore, 1, -1 do
		local ok, err = pcall(run.restore[i])
		if not ok then ns.Log("demo", "put back failed: " .. tostring(err)) end
	end
	if ns.db then ns.db.debugDemoRestore = nil end
	RefreshAll()
	if countdownText then countdownText:SetText("") captionText:SetText("") end
	local took = GetTime() - run.started
	ns.Log("demo", ("%s: %s after %.1f s"):format(run.demo.key, why or "done", took))
	ns.Print(("Demo %s %s (%.0f s)."):format(run.demo.name, why or "done", took))
	StopCue(run, why)
	if RefreshHub then RefreshHub() end
end

local function Resume()
	local run = current
	run.wakeAt, run.waitTest = nil, nil
	local ok, err = coroutine.resume(run.co)
	if current ~= run then return end -- (it finished itself meanwhile)
	if not ok then
		ns.Print("Demo error: " .. tostring(err))
		Finish("stopped by an error")
	elseif coroutine.status(run.co) == "dead" then
		Finish()
	end
end

local function OnUpdate()
	local run = current
	if not run then return end
	local now = GetTime()
	if run.demo.still and ns.playerMoving and not run.countdownUntil then
		Finish("stopped: you moved")
		return
	end
	if run.countdownUntil then
		-- (the numbers, then leadIn seconds of a clear screen before it starts)
		local left = math.ceil(run.countdownUntil - run.leadIn - now)
		countdownText:SetText(left > 0 and tostring(left) or "")
		if now >= run.countdownUntil then
			run.countdownUntil = nil
			run.started = now
			Resume()
		end
	elseif run.captionUntil and now >= run.captionUntil then
		run.captionUntil = nil
		captionText:SetText("")
	end
	if not current or run.countdownUntil then return end
	if run.waitTest then
		local ok, done = pcall(run.waitTest)
		if (ok and done) or now >= run.waitUntil then
			run.waitResult = ok and done or false
			Resume()
		end
	elseif run.wakeAt and now >= run.wakeAt then
		Resume()
	end
end

-- The director a script gets: run is the run it belongs to.
local function Director(run)
	local d = {}
	local remembered = {}
	-- Something to put back as the demo ends.
	function d.Restore(fn)
		run.restore[#run.restore + 1] = fn
	end
	-- Remember a setting's value before the first change (put back at the end,
	-- or after a reload).
	local function Remember(path, original, putBack)
		local id = table.concat(path, "\1")
		if remembered[id] then return end
		remembered[id] = true
		ns.db.debugDemoRestore = ns.db.debugDemoRestore or {}
		ns.db.debugDemoRestore[id] = { path = path, value = original }
		d.Restore(putBack or function() Write(path, original) end)
	end
	function d.Wait(seconds)
		run.wakeAt = GetTime() + (seconds or 0)
		coroutine.yield()
	end
	-- Waits till test() is true or timeout seconds pass; true if it came true.
	function d.WaitUntil(test, timeout)
		run.waitTest, run.waitUntil = test, GetTime() + (timeout or 30)
		coroutine.yield()
		return run.waitResult
	end
	-- f(t) every frame for seconds, t going 0 to 1 (eased in and out).
	function d.Animate(seconds, f)
		local start = GetTime()
		while true do
			local t = math.min(1, (GetTime() - start) / seconds)
			f(t * t * (3 - 2 * t))
			if t >= 1 then return end
			d.Wait(0)
		end
	end
	function d.Cue(text)
		ns.Log("demo", ("%s +%.1fs %s"):format(run.demo.key, GetTime() - run.started, text))
	end
	function d.Caption(text, seconds)
		if not Settings().captions then return end
		Overlay()
		local bar = UIParent:GetHeight() * (ns.db.letterboxSize or 0)
		overlay.caption:ClearAllPoints()
		overlay.caption:SetPoint("BOTTOM", overlay, "BOTTOM", 0, (bar + 40) / 1.5)
		captionText:SetText(text)
		run.captionUntil = GetTime() + (seconds or 3)
	end
	function d.Slash(text)
		ns.HandleSlash(text)
	end
	function d.Emote(token)
		PerformEmote(token)
	end
	function d.Set(key, value)
		Remember({ key }, rawget(ns.db, key))
		ns.db[key] = value
		RefreshAll()
	end
	function d.SetIn(tableKey, key, value)
		local t = ns.db[tableKey]
		if type(t) ~= "table" or not key then return end
		Remember({ tableKey, key }, t[key])
		t[key] = value
		RefreshAll()
	end
	-- CineMode on or off (put back as it was).
	function d.Cine(on)
		local was = ns.db.enabled and true or false
		Remember({ "enabled" }, ns.db.enabled, function()
			if (ns.db.enabled and true or false) ~= was then ns.SetEnabled(was) end
		end)
		if (ns.db.enabled and true or false) ~= on then ns.SetEnabled(on) end
	end
	-- The UI hidden (keeping the look) or shown, put back as it was.
	local uiWas
	function d.HideUI(hidden)
		if uiWas == nil then
			uiWas = UIParent:IsShown()
			d.Restore(function()
				if UIParent:IsShown() ~= uiWas then ns.ToggleUI() end
			end)
		end
		if UIParent:IsShown() == hidden then ns.ToggleUI() end
	end
	-- A tint preset here, whatever the zone's or area's own preset.
	function d.Tint(preset)
		local zone = GetRealZoneText()
		if zone and zone ~= "" then d.SetIn("zonePresets", zone, nil) end
		local area = ns.GetAreaTintInfo and ns.GetAreaTintInfo()
		if area then d.SetIn("zonePresets", area, nil) end
		d.Set("tintPreset", preset)
	end
	-- A camera's Test (CameraTests.lua) for seconds (at most its 30); false if
	-- it couldn't start.
	function d.Cam(section, seconds)
		if not ns.CameraTestStart(section) then
			d.Cue("couldn't start " .. section)
			return false
		end
		d.Restore(ns.CameraTestStop)
		d.Cue(section)
		d.WaitUntil(function() return ns.CameraTestLeft(section) == nil end, seconds)
		ns.CameraTestStop()
		return true
	end
	-- Another demo inside this one (a section's reel): its script with a
	-- director of its own, what it changed put back as it ends, before the
	-- next (or by this one's end, if stopped meanwhile); or a tool, run, then
	-- seconds waited. Skipped where it can't run.
	function d.Play(key, seconds)
		local demo = byKey[key]
		if not demo then return end
		if demo.needs and not demo.needs() then
			d.Cue("skipped " .. key)
			return
		end
		d.Cue("play " .. key)
		d.Caption(demo.name, 3)
		if not demo.script then
			local ok, err = pcall(demo.run)
			if not ok then d.Cue("error: " .. tostring(err)) end
			d.Wait(seconds or 5)
			return
		end
		-- (its waits and captions go on this run: only its own things apart)
		local sub = setmetatable({ demo = demo, restore = {} }, { __index = run, __newindex = run })
		local function PutBack()
			local list = rawget(sub, "restore")
			rawset(sub, "restore", {})
			for i = #list, 1, -1 do pcall(list[i]) end
			RefreshAll()
		end
		d.Restore(PutBack)
		demo.script(Director(sub))
		PutBack()
		d.Wait(1)
	end
	return d
end

local function Stop()
	if current then
		Finish("stopped")
	end
end
ns.StopDemo = Stop

local function Run(key, fromSettings)
	local demo = byKey[key]
	if not demo then
		ns.Print(("No demo called %s: /cine demo list"):format(tostring(key)))
		return
	end
	if demo.needs then
		local ok, why = demo.needs()
		if not ok then
			ns.Print(("Demo %s: %s."):format(demo.name, why))
			return
		end
	end
	if not ns.db then return end
	Stop()
	-- (the last one's Stop recording: gone as this one starts; true if it
	-- hid the hub and hadn't brought it back yet)
	local hubWaiting = HideStopCue(false)
	if fromSettings and not key:find("^tour") and key ~= "menu-look" then CloseSettings() end
	if not demo.script then
		if hubWaiting and hub then hub:Show() end
		local ok, err = pcall(demo.run)
		if not ok then ns.Print("Demo error: " .. tostring(err)) end
		if RefreshHub then RefreshHub() end
		return
	end
	local settings = Settings()
	local run = { demo = demo, restore = {}, started = GetTime() }
	run.co = coroutine.create(function() demo.script(run.d) end)
	run.d = Director(run)
	current = run
	if hubWaiting then
		run.hidHub = true
	elseif hub and hub:IsShown() and settings.hideHub then
		hub:Hide()
		run.hidHub = true
	end
	Overlay()
	ns.Log("demo", "start " .. key)
	if settings.countdown + settings.leadIn > 0 then
		run.leadIn = settings.leadIn
		run.countdownUntil = GetTime() + settings.countdown + settings.leadIn
	else
		run.wakeAt = GetTime() -- (first resume next frame)
	end
	ns.SetOnUpdate(driver, OnUpdate)
	if RefreshHub then RefreshHub() end
end
ns.RunDemo = Run

-- ---------------------------------------------------------------------------
-- The list (in the hub window and on the dev settings page)
-- ---------------------------------------------------------------------------

local function Text(parent, font, text, color)
	local fs = parent:CreateFontString(nil, "OVERLAY", font)
	fs:SetJustifyH("LEFT")
	fs:SetText(text or "")
	if color then fs:SetTextColor(color[1], color[2], color[3]) end
	return fs
end

local lists = {} -- every list made: its Run buttons, to show Stop on the running one
local pageStop -- (the settings page's Stop button, greyed while nothing runs)

local function DemoTip(row, demo)
	row:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(demo.name, 1, 0.82, 0)
		if demo.tip then GameTooltip:AddLine(demo.tip, 1, 1, 1, true) end
		GameTooltip:AddLine(demo.script and "Script: runs on its own, puts everything back as it ends."
			or "Tool: runs once.", 0.6, 0.6, 0.6, true)
		GameTooltip:AddLine("/cine demo " .. demo.key, 0.5, 0.8, 1)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- The list in parent, width wide; returns its height.
local function BuildList(parent, width, fromSettings)
	local list = { buttons = {} }
	lists[#lists + 1] = list
	local y = 0
	for _, group in ipairs(GROUPS) do
		local head = Text(parent, "GameFontNormalLarge", group, GOLD)
		head:SetPoint("TOPLEFT", 4, -y - 8)
		y = y + HEAD_H
		for _, demo in ipairs(demos) do
			if demo.group == group then
				local row = CreateFrame("Frame", nil, parent)
				row:SetSize(width, ROW_H)
				row:SetPoint("TOPLEFT", 0, -y)
				row:EnableMouse(true)
				DemoTip(row, demo)
				local button = ns.PanelButton(row)
				button:SetSize(52, 20)
				button:SetPoint("LEFT", 8, 0)
				button:SetText("Run")
				button:SetScript("OnClick", function()
					if current and current.demo == demo then Stop() else Run(demo.key, fromSettings) end
				end)
				button.demo = demo
				list.buttons[#list.buttons + 1] = button
				local name = Text(row, "GameFontHighlight", demo.name, SOFT)
				name:SetPoint("LEFT", button, "RIGHT", 8, 0)
				name:SetPoint("RIGHT", row, "RIGHT", -64, 0)
				name:SetWordWrap(false)
				local kind = Text(row, "GameFontDisableSmall", demo.script and "script" or "tool", DIM)
				kind:SetPoint("RIGHT", row, "RIGHT", -8, 0)
				y = y + ROW_H
			end
		end
		y = y + 6
	end
	return y + 8
end

function RefreshHub()
	for _, list in ipairs(lists) do
		for _, button in ipairs(list.buttons) do
			local running = current and current.demo == button.demo
			button:SetText(running and "Stop" or "Run")
		end
	end
	if pageStop then
		pageStop:SetEnabled(current ~= nil)
		pageStop.status:SetText(current and ("Running: " .. current.demo.name) or "Nothing running.")
	end
	if hub then
		hub.status:SetText(current and ("Running: " .. current.demo.name) or "Nothing running.")
		local s = Settings()
		hub.countdown:SetText(("Countdown: %d s"):format(s.countdown))
		hub.pages:SetText(("Pages: %d s"):format(s.pageSeconds))
		hub.leadIn:SetText(("Lead-in: %d s"):format(s.leadIn))
		hub.hideHub:SetChecked(s.hideHub)
		hub.captions:SetChecked(s.captions)
	end
end

local function Check(parent, label, key, tip)
	local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	check:SetSize(22, 22)
	if ns.SkinCheck then ns.SkinCheck(check) end
	local text = Text(check, "GameFontHighlightSmall", label)
	text:SetPoint("LEFT", check, "RIGHT", 2, 0)
	check:SetScript("OnClick", function(self) Settings()[key] = self:GetChecked() and true or false end)
	check:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(tip, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	check:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return check
end

local function Cycle(parent, width, key, values, tip)
	local button = ns.PanelButton(parent)
	button:SetSize(width, 22)
	button:SetScript("OnClick", function()
		local s = Settings()
		local nextValue = values[1]
		for i, value in ipairs(values) do
			if value == s[key] then nextValue = values[i % #values + 1] end
		end
		s[key] = nextValue
		RefreshHub()
	end)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(tip, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return button
end

local function CreateScroll(parent)
	local ok, scroll = pcall(CreateFrame, "ScrollFrame", nil, parent, "ScrollFrameTemplate")
	if ok and scroll and scroll.ScrollBar then
		return scroll, 22
	end
	if ok and scroll then scroll:Hide() end
	return CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate"), 28
end

local function CreateHub()
	hub = CreateFrame("Frame", "CinematicDemoHub", UIParent, BackdropTemplateMixin and "BackdropTemplate")
	hub:SetSize(HUB_W, HUB_H)
	hub:SetPoint("RIGHT", UIParent, "RIGHT", -40, 0)
	hub:SetFrameStrata("DIALOG")
	hub:SetToplevel(true)
	hub:EnableMouse(true)
	hub:SetMovable(true)
	hub:SetClampedToScreen(true)
	hub:RegisterForDrag("LeftButton")
	hub:SetScript("OnDragStart", hub.StartMoving)
	hub:SetScript("OnDragStop", hub.StopMovingOrSizing)
	if hub.SetBackdrop then
		hub:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 } })
	end
	if ns.SkinWindow then ns.SkinWindow(hub) end
	tinsert(UISpecialFrames, "CinematicDemoHub") -- Escape closes it

	local title = Text(hub, "GameFontNormalLarge", "|cffff4040DEV|r Demo Hub")
	title:SetPoint("TOPLEFT", 14, -12)
	local close = CreateFrame("Button", nil, hub, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)
	if ns.SkinClose then ns.SkinClose(close) end

	local stop = ns.PanelButton(hub)
	stop:SetSize(70, 22)
	stop:SetPoint("TOPLEFT", 12, -38)
	stop:SetText("Stop")
	stop:SetScript("OnClick", Stop)
	hub.countdown = Cycle(hub, 110, "countdown", { 0, 3, 5 },
		"Seconds of big numbers in the middle of the screen before a script starts: start recording, press " ..
		"Run, and cut the numbers out later.")
	hub.countdown:SetPoint("LEFT", stop, "RIGHT", 6, 0)
	hub.pages = Cycle(hub, 90, "pageSeconds", { 3, 4, 6, 8 }, "How long the settings tours stay on each page.")
	hub.pages:SetPoint("LEFT", hub.countdown, "RIGHT", 6, 0)
	hub.leadIn = Cycle(hub, 90, "leadIn", { 0, 2, 3, 5 },
		"Seconds of a clear screen after the countdown before the script starts, so the take has room to " ..
		"cut in.")
	hub.leadIn:SetPoint("LEFT", hub.pages, "RIGHT", 6, 0)
	hub.hideHub = Check(hub, "Hide while running", "hideHub",
		"Hide this window while a script runs (it comes back when the script ends).")
	hub.hideHub:SetPoint("TOPLEFT", stop, "BOTTOMLEFT", -2, -4)
	hub.captions = Check(hub, "Captions", "captions",
		"Scripts that step through things (tints, moods, cameras) name each on screen, above the letterbox. " ..
		"Off: add your own captions when editing.")
	hub.captions:SetPoint("LEFT", hub.hideHub, "RIGHT", 130, 0)
	hub.status = Text(hub, "GameFontHighlightSmall", "", DIM)
	hub.status:SetPoint("TOPLEFT", hub.hideHub, "BOTTOMLEFT", 4, -4)

	local scroll, barWidth = CreateScroll(hub)
	scroll:SetPoint("TOPLEFT", 10, -112)
	scroll:SetPoint("BOTTOMRIGHT", -10 - barWidth, 10)
	local content = CreateFrame("Frame", nil, scroll)
	local width = HUB_W - 20 - barWidth
	content:SetSize(width, BuildList(content, width))
	scroll:SetScrollChild(content)
	hub:SetScript("OnShow", RefreshHub)
	RefreshHub()
end

local function ToggleHub()
	if not hub then CreateHub() hub:Show() return end
	hub:SetShown(not hub:IsShown())
end

-- ---------------------------------------------------------------------------
-- /cine demo and the dev settings page
-- ---------------------------------------------------------------------------

function ns.DemoCommand(arg)
	arg = arg or ""
	if arg == "" then
		ToggleHub()
	elseif arg == "stop" then
		if current then Stop() else ns.Print("No demo running.") end
	elseif arg == "list" then
		ns.Print("demos (/cine demo <name> runs one, /cine demo stop stops it):")
		for _, group in ipairs(GROUPS) do
			local keys = {}
			for _, demo in ipairs(demos) do
				if demo.group == group then keys[#keys + 1] = demo.key end
			end
			print("  |cffffd100" .. group .. ":|r " .. table.concat(keys, ", "))
		end
	else
		Run(arg)
	end
end

-- The Dev hub's Demo Commands page (Options.lua calls it, the dev copy only).
function ns.CreateDemoHubPage(kit)
	local canvas, content = kit.CreateScrollPage(true)
	local title = kit.Label(content, "GameFontNormalLarge", "Demo Commands")
	title:SetPoint("TOPLEFT", 16, -16)
	local intro = kit.PageIntro(content, title, "Every demo tool in one place, for recording the videos. " ..
		"Scripts run a shot on their own and put everything back as they end. Run one from here (the " ..
		"settings close first) or from the Demo Hub window, which stays out of the way: /cine demo opens it, " ..
		"/cine demo <name> runs one, /cine demo stop stops it.")
	pageStop = ns.PanelButton(content)
	pageStop:SetSize(70, 22)
	pageStop:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -10)
	pageStop:SetText("Stop")
	pageStop:SetScript("OnClick", Stop)
	pageStop.status = Text(content, "GameFontHighlight", "", SOFT)
	pageStop.status:SetPoint("LEFT", pageStop, "RIGHT", 8, 0)
	local open = ns.PanelButton(content)
	open:SetSize(160, 22)
	open:SetPoint("TOPLEFT", pageStop, "BOTTOMLEFT", 0, -8)
	open:SetText("Open Demo Hub")
	open:SetScript("OnClick", function()
		CloseSettings()
		if not hub then CreateHub() end
		hub:Show()
	end)
	local holder = CreateFrame("Frame", nil, content)
	holder:SetPoint("TOPLEFT", open, "BOTTOMLEFT", 0, -10)
	holder:SetSize(560, BuildList(holder, 560, true))
	canvas:HookScript("OnShow", function()
		RefreshHub()
		kit.FitContentHeight(content)
	end)
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Demo Commands", "Demo Commands")
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:SetScript("OnEvent", function(self)
	self:UnregisterAllEvents()
	RestoreLeftovers()
end)
