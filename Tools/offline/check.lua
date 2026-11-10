-- The profile modules' checks (ProfileModules.lua) on both clients, outside
-- the game. From the repo root:
--
--   lua5.1 Tools/offline/check.lua
--   python -I Tools/offline/run.py Tools/offline/check.lua    (no lua5.1: Windows)
--
-- Add --update after it when a built-in profile's settings changed on
-- purpose: it writes them to profile-settings-<client>.txt (see below).
--
-- Loads the addon on each client and build (load.lua: each in a Lua of its
-- own, so one's settings don't carry into the next) and runs
-- ns.CheckModules: each module writing only inside its scope, no two of a
-- profile's modules setting the same thing, every built-in's modules there.
-- Also: the files loading without errors, every scope entry on at least one
-- client's options, and every module used by a built-in or a slot's choice.
-- Notes (two choices of a slot that come out the same) are listed but pass. Exits 1 on any
-- problem.
--
-- And each built-in profile's settings, as they come out
-- (what each changes from the defaults), against the ones saved in
-- Tools/offline/profile-settings-<client>.txt: a change to a module or a
-- choice changes the profiles using it. Any difference is a problem until
-- it's saved with --update.

-- (The Lua that runs each run: run.py sets CINE_LUA to itself.)
local LUA = os.getenv("CINE_LUA") or "lua5.1"
local update = arg[1] == "--update"

local RUNS = {
	{ "forever", "Cinematic.toc" }, { "retail", "Cinematic.toc" },
	{ "forever", "CinematicDev.toc" }, { "retail", "CinematicDev.toc" },
}

-- One run (lua5.1 check.lua <client> <toc>): its lines, tab-separated.
if arg[1] and not update then
	local client, toc = arg[1], arg[2]
	local ns, wow = dofile("Tools/offline/load.lua")(client, toc)
	for _, warning in ipairs(wow.warnings) do
		-- (The minimap button compares the stand-in's numbers: not the addon's.)
		if not warning:find("^PLAYER_LOGIN: MinimapButton") then print("problem\t" .. warning) end
	end
	-- Your own lines and Hide your messages' exception (Chat.lua): lines you type
	-- with no bubble show chat, emotes and loot don't, and it's all off without it.
	do
		local function Problem(text) print("problem\town lines: " .. text) end
		local filters = {}
		local keptFilter, keptCVar = rawget(_G, "ChatFrame_AddMessageEventFilter"), rawget(_G, "GetCVarBool")
		_G.ChatFrame_AddMessageEventFilter = function(event, filter) filters[event] = filter end
		ns.RegisterChatPeek()
		local me = UnitName("player")
		local frame = { IsShown = function() return true end }
		local function Peeks(event, author)
			ns.chatPeekUntil[frame] = nil
			filters[event](frame, event, "hello", author or me)
			return ns.chatPeekUntil[frame] ~= nil
		end
		local db = ns.db
		if db.chatOwnNoBubble ~= true then Problem("the exception isn't on by default") end
		local kept = { db.chatPeek, db.handleChat, db.chatHideOwn, db.chatOwnNoBubble }
		local keptGuild, keptChannels = db.chatPeekTypes.guild, db.chatPeekChannels
		db.chatPeek, db.handleChat, db.chatHideOwn, db.chatOwnNoBubble = true, true, true, true
		for _, event in ipairs({ "CHAT_MSG_GUILD", "CHAT_MSG_PARTY" }) do
			if not Peeks(event) then Problem(event .. " with no bubble didn't show chat") end
		end
		-- (Rows that are off are for other people's lines: General off, as players have it.)
		db.chatPeekTypes.guild, db.chatPeekChannels = false, false
		if not Peeks("CHAT_MSG_GUILD") then Problem("a guild line hid with the guild row off") end
		if not Peeks("CHAT_MSG_CHANNEL") then Problem("a channel line hid with the channel off") end
		if Peeks("CHAT_MSG_GUILD", "Someone") then Problem("someone else's guild line showed with the row off") end
		db.chatPeekTypes.guild, db.chatPeekChannels = keptGuild, keptChannels
		-- (A whisper to no one: the game sends only this system line.)
		local keptError = rawget(_G, "ERR_CHAT_PLAYER_NOT_FOUND_S")
		_G.ERR_CHAT_PLAYER_NOT_FOUND_S = "No player named '%s' is currently playing."
		ns.chatPeekUntil[frame] = nil
		filters.CHAT_MSG_SYSTEM(frame, "CHAT_MSG_SYSTEM", "No player named 'Test' is currently playing.", "")
		if not ns.chatPeekUntil[frame] then Problem("a whisper to no one didn't show chat") end
		ns.chatPeekUntil[frame] = nil
		filters.CHAT_MSG_SYSTEM(frame, "CHAT_MSG_SYSTEM", "Some other system line.", "")
		if ns.chatPeekUntil[frame] then Problem("another system line showed chat") end
		_G.ERR_CHAT_PLAYER_NOT_FOUND_S = keptError
		if not Peeks("CHAT_MSG_WHISPER_INFORM", "Someone") then Problem("a sent whisper didn't show chat") end
		for _, event in ipairs({ "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE" }) do
			if Peeks(event) then Problem(event .. " showed chat") end
		end
		_G.GetCVarBool = function() return true end -- (bubbles on: the line waits for its bubble)
		if Peeks("CHAT_MSG_SAY") then Problem("a say showed chat before its bubble could") end
		_G.GetCVarBool = keptCVar
		db.chatOwnNoBubble = false
		for _, event in ipairs({ "CHAT_MSG_GUILD", "CHAT_MSG_PARTY" }) do
			if Peeks(event) then Problem(event .. " showed chat with the exception off") end
		end
		if Peeks("CHAT_MSG_WHISPER_INFORM", "Someone") then Problem("a sent whisper showed chat with it off") end
		db.chatHideOwn = false
		if not Peeks("CHAT_MSG_WHISPER_INFORM", "Someone") then Problem("a sent whisper hid with Hide your messages off") end
		db.chatPeek, db.handleChat, db.chatHideOwn, db.chatOwnNoBubble = kept[1], kept[2], kept[3], kept[4]
		_G.ChatFrame_AddMessageEventFilter = keptFilter
		ns.chatPeekUntil[frame] = nil
	end
	-- The game's /follow moves you with no key held: moving by hand, not auto-run.
	do
		local function Problem(text) print("problem\t/follow: " .. text) end
		local kept = {}
		for name, value in pairs({ IsMouseButtonDown = false, UnitOnTaxi = false, IsFlying = false, GetUnitSpeed = 7 }) do
			kept[name], _G[name] = rawget(_G, name), function() return value end
		end
		-- (Each ask a frame of its own: the answers are kept for the frame,
		-- and the events below come between frames in the game.)
		local clock = 0
		kept.GetTime, _G.GetTime = rawget(_G, "GetTime"), function() clock = clock + 0.001 return clock end
		ns.playerMoving, ns.movingSince, ns.autoRunning = true, -5, false
		if not ns.IsAutoRunning() then Problem("hands-free moving isn't auto-run without it") end
		ns.autoRunning = false
		wow.Fire("AUTOFOLLOW_BEGIN", "Someone")
		if ns.IsAutoRunning() then Problem("counted as auto-run") end
		if ns.autoRunning then Problem("auto-run inferred") end
		if not ns.MovingManually() then Problem("not moving by hand") end
		wow.Fire("AUTOFOLLOW_END")
		if ns.MovingManually() or not ns.IsAutoRunning() then Problem("still on after it ended") end
		wow.Fire("AUTOFOLLOW_BEGIN", "Someone")
		wow.Fire("PLAYER_ENTERING_WORLD")
		if ns.autoFollowing then Problem("still on after a loading screen") end
		ns.playerMoving, ns.movingSince, ns.autoRunning = false, nil, false
		for _, name in ipairs({ "IsMouseButtonDown", "UnitOnTaxi", "IsFlying", "GetUnitSpeed", "GetTime" }) do _G[name] = kept[name] end
	end
	-- The scene (ns.DecideScene, Camera.lua): its table is ns.scene, it sets
	-- ns.activeCam to its own cam, standing still past the wait is the idle
	-- scene, and moving ends it (Tools/camera-director-plan.md, phase 1).
	do
		local function Problem(text) print("problem\tScene: " .. text) end
		local db = ns.db
		local kept = { db.idleOrbit, ns.stillSince, ns.activeCam, ns.playerMoving }
		local keptApi = {}
		for name, value in pairs({ IsMouseButtonDown = false, UnitOnTaxi = false, IsFlying = false, GetUnitSpeed = 7 }) do
			keptApi[name], _G[name] = rawget(_G, name), function() return value end
		end
		db.idleOrbit = true
		ns.playerMoving, ns.stillSince = false, -1000
		local scene = ns.DecideScene(true, 0, false, false)
		if scene ~= ns.scene then Problem("not ns.scene") end
		if ns.activeCam ~= scene.cam then Problem(("ns.activeCam %s, scene %s"):format(tostring(ns.activeCam), tostring(scene.cam))) end
		if scene.idle and scene.cam ~= "idle" and not scene.vista and not scene.cozy and not scene.fish then
			Problem("idle with no event, but its camera is " .. tostring(scene.cam))
		end
		if scene.cam == "idle" and not scene.idle then Problem("the idle camera without the idle scene") end
		ns.playerMoving = true
		scene = ns.DecideScene(true, 0, false, true)
		if scene.idle or scene.cam == "idle" then Problem("still idle while moving") end
		if ns.stillSince ~= nil then Problem("moving didn't end the standing-still timer") end
		db.idleOrbit, ns.stillSince, ns.activeCam, ns.playerMoving = kept[1], kept[2], kept[3], kept[4]
		for name in pairs(keptApi) do _G[name] = keptApi[name] end
	end
	-- The camera director (Director.lua): decides once a frame at most, not
	-- again with nothing changed until its tick, then on the tick, and at
	-- once when woken (phase 2).
	do
		local function Problem(text) print("problem\tDirector: " .. text) end
		local keptTime, t = GetTime, 1000
		_G.GetTime = function() return t end
		local stats = ns.directorStats
		ns.DirectorStep() -- (settles what it's seen)
		t = t + 0.02
		ns.DirectorStep()
		local decides = stats.decides
		t = t + 0.02
		ns.DirectorStep()
		if stats.decides ~= decides then Problem("decided again with nothing changed, before its tick") end
		t = t + 0.2
		ns.DirectorStep()
		if stats.decides ~= decides + 1 then Problem("didn't decide on its tick") end
		decides = stats.decides
		t = t + 0.02
		ns.WakeDirector("check")
		ns.DirectorStep()
		if stats.decides ~= decides + 1 then Problem("didn't decide at once when woken") end
		ns.WakeDirector("check")
		ns.DirectorStep()
		if stats.decides ~= decides + 1 then Problem("decided twice in one frame") end
		t = t + 0.02
		ns.DirectorStep()
		if stats.decides ~= decides + 2 then Problem("a wake in a frame it had stepped in was lost") end
		-- The orbit asleep (phase 3): quiet with no camera, not with one;
		-- stays asleep through a quiet step, and the director wakes it.
		local keptScript, keptCine = ns.orbitFrame:GetScript("OnUpdate"), ns.lastCinematic
		if not ns.OrbitOnUpdate then Problem("no ns.OrbitOnUpdate to wake the orbit with") end
		if not ns.OrbitQuiet({}) then Problem("not quiet with no scene") end
		if ns.OrbitQuiet({ cam = "idle" }) then Problem("quiet with a camera on") end
		if ns.OrbitQuiet({ dead = true }) then Problem("quiet dead") end
		if ns.OrbitQuiet({ onTaxi = true }) then Problem("quiet on a flight") end
		ns.lastCinematic = true
		if ns.OrbitQuiet({ idle = true }) then Problem("quiet in CineMode standing still") end
		ns.lastCinematic = false
		if not ns.OrbitQuiet({ idle = true }) then Problem("not quiet standing still out of CineMode") end
		-- (A camera moving the view with its own code: its script, the quest
		-- camera, Chat Cam. Not one of ours with no script playing.)
		if not ns.OrbitQuiet({ cam = "quest" }) then Problem("not quiet in the quest camera") end
		local keptScript2, keptKey = ns.PlayingCameraScript, ns.PlayingCameraKey
		ns.PlayingCameraScript, ns.PlayingCameraKey = function() return {} end, function() return "run" end
		if not ns.OrbitQuiet({ cam = "run" }) then Problem("not quiet with the run camera playing as its script") end
		ns.PlayingCameraScript, ns.PlayingCameraKey = keptScript2, keptKey
		if ns.OrbitQuiet({ cam = "run" }) then Problem("quiet with the run camera's own code") end
		ns.orbitFrame:SetScript("OnUpdate", nil)
		t = t + 0.02
		ns.DirectorStep()
		if ns.OrbitQuiet(ns.scene) and not ns.OrbitAsleep() then Problem("a quiet step woke the orbit") end
		ns.WakeOrbit()
		if ns.OrbitAsleep() or ns.orbitFrame:GetScript("OnUpdate") ~= ns.OrbitOnUpdate then
			Problem("ns.WakeOrbit didn't wake it")
		end
		-- (Awake, out of CineMode with nothing on: a few frames and it sleeps.)
		for _ = 1, 3 do
			t = t + 0.02
			if not ns.OrbitAsleep() then ns.UpdateOrbit(false, 0.02) end
		end
		if not ns.OrbitAsleep() then Problem("awake out of CineMode with nothing on, after 3 frames") end
		ns.orbitFrame:SetScript("OnUpdate", keptScript)
		ns.lastCinematic = keptCine
		-- ns.ActiveEvent (phase 4): with the director running, worked out once
		-- per decision, not each frame; again after the next decision.
		local wasRunning = ns.DirectorRunning()
		ns.SetDirectorRunning(true)
		-- (Counted by ns.ShotBase, which each working out ends with.)
		local keptShot, works = ns.ShotBase, 0
		ns.ShotBase = function(...) works = works + 1 return keptShot(...) end
		t = t + 0.02
		ns.WakeDirector("check")
		ns.DirectorStep()
		if works == 0 then Problem("a decision didn't work ns.ActiveEvent out again") end
		local after = works
		for _ = 1, 3 do
			t = t + 0.02
			ns.ActiveEvent()
		end
		if works ~= after then
			Problem(("ns.ActiveEvent worked out %d more times between decisions"):format(works - after))
		end
		ns.ShotBase = keptShot
		-- The nameplates pass (Effects.lua): outside CineMode, settled, it's
		-- skipped until something it goes by changes or its 0.5 s are up; in
		-- CineMode it runs every tick. (Counted by ns.PlateSuffix: once or more a pass.)
		local keptPlates, keptSuffix, passes = ns.db.handlePlates, ns.PlateSuffix, 0
		ns.db.handlePlates = true
		ns.PlateSuffix = function(...) passes = passes + 1 return keptSuffix(...) end
		for _ = 1, 4 do
			t = t + 0.03
			ns.UpdatePlates(false, 0.03)
		end
		local settledPasses = passes
		for _ = 1, 3 do
			t = t + 0.03
			ns.UpdatePlates(false, 0.03)
		end
		if ns.plates.settled and passes ~= settledPasses then
			Problem(("nameplates: %d passes outside CineMode with nothing changed"):format(passes - settledPasses))
		end
		if not ns.plates.settled then print("note\tnameplates never settled here: the skip isn't checked") end
		t = t + 0.6
		ns.UpdatePlates(false, 0.03)
		if ns.plates.settled and passes == settledPasses then Problem("nameplates: no pass after its 0.5 s") end
		settledPasses = passes
		for _ = 1, 2 do
			t = t + 0.03
			ns.UpdatePlates(true, 0.03)
		end
		if passes < settledPasses + 2 then Problem("nameplates: skipped in CineMode") end
		ns.PlateSuffix, ns.db.handlePlates = keptSuffix, keptPlates
		-- The rule facts (Frames.lua): held 0.1 s across frames, worked out
		-- afresh after that or when the target changes. (Counted by
		-- ns.GetPlaceType, which each working out asks once.)
		local keptPlace, works2 = ns.GetPlaceType, 0
		ns.GetPlaceType = function(...) works2 = works2 + 1 return keptPlace(...) end
		t = t + 1
		ns.RuleFacts(false)
		local w = works2
		t = t + 0.02
		ns.RuleFacts(false)
		t = t + 0.02
		ns.RuleFacts(true)
		if works2 ~= w then Problem("rule facts worked out again within 0.1 s") end
		t = t + 0.2
		ns.RuleFacts(false)
		if works2 == w then Problem("rule facts not worked out again after 0.1 s") end
		w = works2
		t = t + 0.02
		wow.Fire("PLAYER_TARGET_CHANGED")
		ns.RuleFacts(false)
		if works2 == w then Problem("rule facts not worked out again as the target changed") end
		ns.GetPlaceType = keptPlace
		-- A row's Show in answer (ns.RuleShows): kept while the facts' stamp
		-- holds, worked out again as it changes (a fight, the next working out),
		-- and never kept for facts of the caller's own.
		local keptRules = ns.db.frameRules
		ns.db.frameRules = { ["check:row"] = "combat" }
		t = t + 1
		local facts = ns.RuleFacts(false)
		if ns.RuleShows("check:row", facts) ~= false then Problem("rule 'combat' shows out of a fight") end
		facts = ns.RuleFacts(true)
		if ns.RuleShows("check:row", facts) ~= true then Problem("a kept answer outlived the fight word changing") end
		ns.db.frameRules = { ["check:row"] = "not combat" }
		t = t + 0.6
		facts = ns.RuleFacts(true)
		if ns.RuleShows("check:row", facts) ~= false then Problem("a kept answer outlived its rule's change by 0.5 s") end
		if ns.RuleShows("check:row", { combat = false }) ~= true then Problem("an answer kept for the caller's own facts") end
		ns.db.frameRules = keptRules
		-- The camera script watcher's trigger (CameraScripts.lua): the same,
		-- once per decision.
		t = t + 0.02
		ns.WakeDirector("check")
		ns.DirectorStep()
		local _, _, _, afresh = ns.ScriptTriggerNow()
		if not afresh then Problem("the script trigger wasn't worked out afresh after a decision") end
		t = t + 0.02
		_, _, _, afresh = ns.ScriptTriggerNow()
		if afresh then Problem("the script trigger worked out again between decisions") end
		ns.SetDirectorRunning(wasRunning)
		_G.GetTime = keptTime
	end
	-- A new player (load.lua: a fresh install): every page off until a profile's
	-- picked (Profiles.lua), then the profile's own. (The rest: as after a pick.)
	do
		local db = ns.GetDB()
		if db.profileChosen ~= false then print("problem\ta fresh install has a profile picked") end
		for _, key in ipairs(ns.OFF_UNTIL_PICKED) do
			if ns.DEFAULTS[key] ~= nil and db[key] ~= false then -- (nil: the dev copy's only)
				print("problem\tno profile picked: " .. key .. " is on")
			end
		end
		-- (Its settings are in before the stand-in's frames fall short of what
		-- the settings' refresh after needs: Bubbles' GetChildren.)
		-- (Balanced, not the default: Blank Slate has every page off, and the
		-- checks after need its features on.)
		pcall(ns.SetProfile, "Balanced")
		local base = ns.ProfileBase()
		for _, key in ipairs(ns.OFF_UNTIL_PICKED) do
			if ns.IsProfileKey(key) and db[key] ~= base[key] then
				print(("problem\tpicked a profile: %s is %s, not its %s"):format(key, tostring(db[key]),
					tostring(base[key])))
			end
		end
		if db.offUntilPicked then print("problem\tpicked a profile: still off") end
	end
	local problems, _, absent, nowhere, notes = ns.CheckModules(client, ns.ALL_BUILTIN_PROFILES)
	-- Each built-in's settings (the dev build's run: it has every profile).
	if toc == "CinematicDev.toc" then
		local byName, list = {}, {}
		for _, profile in ipairs(ns.ALL_BUILTIN_PROFILES) do
			byName[profile.name] = profile
			list[#list + 1] = profile
		end
		local base = ns.ModuleBase(client)
		for _, profile in ipairs(list) do
			if not profile.client or profile.client == client then
				for _, change in ipairs(ns.ModuleEffect(ns.ResolveModules(profile, client, byName), client, base)) do
					local value = change[3]
					value = type(value) == "table" and ns.SerialValue(value) or tostring(value)
					print(("settings\t%s|%s%s=%s"):format(profile.name, change[1],
						change[2] ~= nil and "." .. tostring(change[2]) or "", value))
				end
			end
		end
	end
	for _, line in ipairs(problems) do print("problem\t" .. line) end
	for _, line in ipairs(notes) do print("note\t" .. line) end
	for key, entries in pairs(absent) do
		for _, entry in ipairs(entries) do print("absent\t" .. key .. "\t" .. entry) end
	end
	for key, settings in pairs(nowhere) do
		for _, setting in ipairs(settings) do print("nowhere\t" .. key .. "\t" .. setting) end
	end
	for _, key in ipairs(ns.ModuleKeys()) do
		local module = ns.GetModule(key)
		if not module.client or module.client == client then print("module\t" .. key) end
	end
	for _, profile in ipairs(ns.ALL_BUILTIN_PROFILES) do
		if not profile.client or profile.client == client then
			for _, entry in ipairs(ns.ResolveModules(profile, client, ns.ALL_BUILTIN_BY_NAME)) do
				print("used\t" .. entry.key)
			end
		end
	end
	-- (Or by a slot's choice: the welcome window's Customize pages.)
	for slot, info in pairs(ns.SLOT_CHOICES) do
		for _, choice in ipairs(info.choices) do
			for _, entry in ipairs(ns.ChoiceModules(slot, choice.part, client) or {}) do
				print("used\t" .. entry.key)
			end
		end
	end
	-- The Cameras page's triggers, in the order they always had (the chat
	-- camera's only where it's loaded).
	local expected = { "Hearth", "Teleport", "Logout", "AFK", "Sit", "SitButton", "Sleep", "Dance", "Kneel", "Stare",
		"Chair", "Weapon", "Campfire", "Fishing", "Still", "Flight", "Quest", "QuestGossip", "Walk", "Run", "Death" }
	if ns.ChatCamCommand then
		expected[#expected + 1] = "Chat"
		expected[#expected + 1] = "ChatNearby"
	end
	local keys = {}
	for i, trigger in ipairs(ns.CAMERA_TRIGGERS) do
		keys[i] = trigger.key
		if ns.CAMERA_TRIGGER[trigger.key] ~= trigger then print("problem\tCamera trigger " .. trigger.key .. " not indexed") end
	end
	if table.concat(keys, ",") ~= table.concat(expected, ",") then
		print("problem\tCamera triggers are " .. table.concat(keys, ",") .. ", not " .. table.concat(expected, ","))
	end
	-- The trigger sources (Triggers.lua) pick as the fixed order before them
	-- did, for every mix of what's on and which triggers have a camera.
	local function OldPick(state, cameraOf)
		local order = { state.departing, state.logout and "Logout", state.afk and "AFK", state.byFire and "Campfire",
			state.emote, state.weapon and "Weapon", state.campfire and "Campfire", state.still and "Still" }
		for i = 1, 8 do
			local camera = order[i] and cameraOf(order[i])
			if camera then return order[i], camera end
		end
	end
	local EMOTES = { false, "Sit", "Fishing", "Hearth" }
	local CAMERA_SETS = {
		{ Hearth = "tele", Teleport = "tele", Logout = "cozy", AFK = "afk", Campfire = "cozy", Sit = "vista",
			Fishing = "fish", Weapon = "cozy", Still = "afk" },
		{ Logout = "cozy", Campfire = "cozy", Fishing = "fish", Still = "afk" },
		{ AFK = "afk", Sit = "vista", Weapon = "cozy" },
		{ Teleport = "tele", Campfire = "cozy" },
		{},
	}
	local mismatches = 0
	for _, cameras in ipairs(CAMERA_SETS) do
		local function CameraOf(key) return cameras[key] end
		for bits = 0, 63 do
			for _, departing in ipairs({ false, "Hearth", "Teleport" }) do
				for _, emote in ipairs(EMOTES) do
					local function Bit(n) return math.floor(bits / 2 ^ n) % 2 == 1 end
					local state = { departing = departing, logout = Bit(0), afk = Bit(1), byFire = Bit(2), emote = emote,
						weapon = Bit(3), campfire = Bit(4), still = Bit(5) }
					local newKey, newCamera = ns.PickTrigger(state, CameraOf)
					local oldKey, oldCamera = OldPick(state, CameraOf)
					if newKey ~= oldKey or newCamera ~= oldCamera then mismatches = mismatches + 1 end
				end
			end
		end
	end
	if mismatches > 0 then
		print(("problem\tTrigger sources pick differently from the old order in %d cases"):format(mismatches))
	end
	-- Our triggers in the library (TriggerLibrary.lua): a priority of its own
	-- moves one past another, an Only if holds one back, Reset undoes both.
	do
		local cams = { AFK = "afk", Sit = "vista" }
		local function CameraOf(key) return cams[key] end
		local state = { afk = true, emote = "Sit" }
		local function Pick() return (ns.PickTrigger(state, CameraOf)) end
		local function OursProblem(text) print("problem\tOur triggers: " .. text) end
		if Pick() ~= "AFK" then OursProblem("AFK doesn't beat /sit to start with") end
		ns.SetTriggerField(ns.OursTriggerId("Sit"), "pri", 50)
		if Pick() ~= "Sit" then OursProblem("/sit at priority 50 doesn't beat AFK") end
		ns.ResetOursTrigger("Sit")
		ns.SetTriggerField(ns.OursTriggerId("AFK"), "cond", "never")
		if Pick() ~= "Sit" then OursProblem("AFK with Only if never isn't held back") end
		ns.ResetOursTrigger("AFK")
		if Pick() ~= "AFK" or ns.OursChanged("AFK") or ns.OursChanged("Sit") then OursProblem("Reset didn't undo them") end
	end
	-- Triggers of your own (CustomTriggers.lua): one added is a row with its
	-- camera, sits after the emotes in the priority list (or first), starts
	-- from its key, and taken off leaves nothing behind.
	local function Problem(text) print("problem\tCustom triggers: " .. text) end
	local function SourceOf(id)
		for _, source in ipairs(ns.TRIGGER_SOURCES) do
			if source.unit and source.unit.scene == id then return source end
		end
	end
	local before = #ns.CAMERA_TRIGGERS
	local id = ns.AddCustomTrigger("key:1", "key", "vista", "Photo mode")
	local rows = ns.GetDB().cameraRows
	if id ~= "MineA" then Problem("the first one's id is " .. tostring(id)) end
	if id then
		if not ns.CAMERA_TRIGGER[id] or #ns.CAMERA_TRIGGERS ~= before + 1 then Problem("not on the Cameras page") end
		local listed = false
		for _, each in ipairs(ns.CameraRowOrder()) do listed = listed or each == id end
		if not listed then Problem("its row isn't in the row order") end
		if ns.CameraRowValue(id, "camera") ~= "vista" then Problem("its camera is " .. tostring(ns.CameraRowValue(id, "camera"))) end
		ns.SetCameraRowValue(id, "music", true)
		if rows[id .. ".music"] ~= true or ns.CameraRowValue(id, "music") ~= true then Problem("music not kept") end
		local source = SourceOf(id)
		if not source or not (source.order > 500 and source.order < 600) then
			Problem("not between the emotes and the weapon: " .. tostring(source and source.order))
		end
		if source and source.Key({}) ~= nil then Problem("on before its key") end
		Cinematic_CustomTrigger(1)
		if source and source.Key({}) ~= id then Problem("its key didn't start it") end
		Cinematic_CustomTrigger(1)
		if source and source.Key({}) ~= nil then Problem("its key didn't stop it") end
		-- (Its trigger is the library's: its priority there moves the scene.)
		local lib = tostring(ns.SceneTriggers(id)[1]):match("^t:(Trig%a+)$")
		if not lib then Problem("its trigger isn't in the library: " .. tostring(ns.SceneTriggers(id)[1])) end
		if lib then ns.SetTriggerField(lib, "pri", 50) end
		source = SourceOf(id)
		if not source or source.order >= 100 then Problem("priority 50 isn't first: " .. tostring(source and source.order)) end
		-- (A scene written before the library moves its trigger in, with its until and its place.)
		rows[id .. ".triggers"], rows[id .. ".until"], rows[id .. ".after"] = "emote:wave", "time:8", "afk"
		ns.CustomTriggersChanged()
		local moved = tostring(ns.SceneTriggers(id)[1]):match("^t:(Trig%a+)$")
		if not moved or ns.TriggerField(moved, "src") ~= "emote:wave" or ns.TriggerField(moved, "ends") ~= "time:8"
			or ns.TriggerPri(moved) ~= 310 or rows[id .. ".until"] or rows[id .. ".after"] then
			Problem("an old scene's trigger didn't move into the library whole")
		end
		local copy = ns.CopyCameraRow(id)
		if copy ~= id .. "2" then Problem("its copy is " .. tostring(copy)) end
		ns.RemoveCustomTrigger(id)
		ns.ClearTriggerLib() -- (its triggers stay in the library: cleared for the checks after)
		ns.SyncCustomTriggers()
		if ns.CAMERA_TRIGGER[id] or #ns.CAMERA_TRIGGERS ~= before or SourceOf(id) then Problem("still there taken off") end
		for key in pairs(rows) do
			if tostring(key):find("^" .. id) then Problem("left behind: " .. key) end
		end
		if rows.custom ~= nil then Problem("its list is " .. tostring(rows.custom)) end
		for _, each in ipairs(ns.CameraRowOrder()) do
			if each:find("^" .. id) then Problem("its row's still in the order: " .. each) end
		end
	end
	-- A built-in trigger deleted (CameraRows' deleted list): its rows go, it
	-- starts no camera, and Add back brings it back as it was.
	local afkCamera = ns.CameraRowValue("AFK", "camera")
	ns.SetTriggerDeleted("AFK", true)
	for _, each in ipairs(ns.CameraRowOrder()) do
		if each:find("^AFK%d?$") then Problem("a deleted trigger's row is still listed: " .. each) end
	end
	if ns.TriggerRowNow("AFK") ~= nil or ns.TriggerSetting("AFK", "camera") ~= "none" then
		Problem("a deleted trigger still picks a camera")
	end
	if ns.DeletedTriggers()[1] ~= "AFK" then Problem("Add back doesn't list it") end
	ns.SetTriggerDeleted("AFK", false)
	local back = false
	for _, each in ipairs(ns.CameraRowOrder()) do back = back or each == "AFK" end
	if not back or ns.CameraRowValue("AFK", "camera") ~= afkCamera or ns.GetDB().cameraRows.deleted ~= nil then
		Problem("Add back didn't bring it back as it was")
	end
	-- A scene a profile has off keeps its camera, ticked off (every built-in
	-- camera in a scene), on any profile; and profiles saved when off meant No
	-- camera or no place ticks move over, cameras that played staying on.
	do
		local base = ns.ProfileBase("Subtle")
		for _, key in ipairs({ "sceneOffCampfire", "sceneOffFishing", "sceneOffQuest", "sceneOffWalk", "sceneOffDeath" }) do
			if base[key] ~= true then Problem("Subtle's " .. key .. " isn't off") end
		end
		if base.eventCampfireCamera ~= "cozy" or base.walkCamera ~= "walk" or base.chatCamera ~= "chat" then
			Problem("a scene Subtle has off lost its camera")
		end
		if base.sceneOffAFK or base.sceneOffFlight then Problem("Subtle's AFK or Flight scene is off") end
		if ns.ProfileBase("Cinema").sceneOffChat ~= false then Problem("Cinema's chat scene isn't on") end
		local db = ns.GetDB()
		local was = db.sceneOffCampfire
		ns.SetCameraRowOn("Campfire", false)
		if db.sceneOffCampfire ~= true or ns.CameraRowOn("Campfire") or ns.TriggerSetting("Campfire", "camera") ~= "none" then
			Problem("a scene ticked off still plays")
		end
		ns.SetCameraRowOn("Campfire", true)
		if db.sceneOffCampfire ~= false or not ns.CameraRowOn("Campfire") then Problem("ticking a scene on didn't take") end
		db.sceneOffCampfire = was
		local old = { eventFishingCamera = "none", eventSitCamera = "cozy", chatCamera = "chat", worldShow = { ["cam:walk"] = false,
			["cam:run"] = true }, cityShow = { ["cam:walk"] = false }, instanceShow = { ["cam:walk"] = false } }
		ns.ScenesOffKeepCameras(old)
		if old.eventFishingCamera ~= "fish" or old.sceneOffFishing ~= true then Problem("a saved No camera didn't move over") end
		if old.sceneOffSit ~= false or old.eventSitCamera ~= "cozy" then Problem("a saved camera of your own was turned off") end
		if old.sceneOffChat ~= false then Problem("a saved chat camera that played was turned off") end
		if old.sceneOffWalk ~= true or old.worldShow["cam:walk"] ~= nil then Problem("a saved walk with no places didn't move over") end
		if old.sceneOffRun ~= false then Problem("a saved run with a place ticked was turned off") end
		if old.sceneOffFlight ~= nil or old.sceneOffStill ~= nil then Problem("a saved profile's untouched scenes were written") end
	end
	-- Built-in scenes with several triggers (CameraRows' SCENE_GROUPS): the
	-- cozy ones are one row to start with, an edit to it reaches every member,
	-- who's in a scene doesn't change by itself, a trigger moved out is a row
	-- of its own (and moved back joins again), moved into another scene takes
	-- its camera, and deleting the group lists it once for Add back.
	local function GroupProblem(text) print("problem\tScene groups: " .. text) end
	local function Listed(id)
		for _, each in ipairs(ns.CameraRowOrder()) do
			if each == id then return true end
		end
	end
	ns.SceneGroupState()
	if not (Listed("Campfire") and not Listed("Dance") and ns.SceneLead("Dance") == "Campfire") then
		GroupProblem("the cozy triggers aren't one scene to start with")
	end
	local danceCamera = ns.CameraRowValue("Dance", "camera")
	ns.EditScene("Campfire", function() ns.SetCameraRowValue("Campfire", "music", true) end)
	if ns.CameraRowValue("Dance", "music") ~= true or Listed("Dance") then GroupProblem("an edit didn't reach a member") end
	ns.EditScene("Campfire", function() ns.SetCameraRowValue("Campfire", "music", ns.DEFAULTS.eventCampfireMusic) end)
	ns.SetCameraRowValue("Dance", "camera", "fish")
	ns.CameraRowsChanged()
	if Listed("Dance") then GroupProblem("a member split off by itself") end
	ns.SetCameraRowValue("Dance", "camera", danceCamera)
	ns.CameraRowsChanged()
	ns.MoveTriggerToScene("Dance", "")
	if not Listed("Dance") or ns.SceneLead("Dance") ~= "Dance" then GroupProblem("a member moved out isn't a row of its own") end
	ns.MoveTriggerToScene("Dance", "Sit")
	if Listed("Dance") or ns.SceneLead("Dance") ~= "Sit" or ns.CameraRowValue("Dance", "camera") ~= ns.CameraRowValue("Sit", "camera") then
		GroupProblem("a trigger moved into Looking out didn't join it")
	end
	ns.MoveTriggerToScene("Dance", "Campfire")
	if Listed("Dance") or ns.SceneLead("Dance") ~= "Campfire" or ns.GetDB().cameraRows["scene:Dance"] ~= nil
		or ns.CameraRowValue("Dance", "camera") ~= danceCamera then
		GroupProblem("a member moved back didn't rejoin its group as it was")
	end
	ns.SetSceneDeleted("Campfire", true)
	local deletedList = ns.DeletedTriggers()
	if #deletedList ~= 1 or deletedList[1] ~= "Campfire" then
		GroupProblem("Add back lists " .. table.concat(deletedList, ",") .. ", not the group once")
	end
	ns.SetSceneDeleted("Campfire", false)
	if #ns.DeletedTriggers() ~= 0 or Listed("Dance") then GroupProblem("the group didn't come back whole") end
	-- My Shots (Shots.lua): a shot follows its camera's numbers until given its
	-- own, a row set to one goes by its camera's mode, a trigger shared with
	-- its shot comes back whole, a tampered string is clamped or refused, and
	-- deleting a shot sends its rows back to its camera.
	local function ShotProblem(text) print("problem\tMy Shots: " .. text) end
	local shot = ns.AddShot("vista", "Wide")
	local trigger = shot and ns.AddCustomTrigger("emote:wave", "move", "shot:" .. shot, "Wave")
	if not (shot and trigger) then
		ShotProblem("couldn't make a shot and a trigger for it")
	else
		if ns.ShotValue(shot, "OrbitBackArc") ~= ns.GetDB().vistaOrbitBackArc then ShotProblem("doesn't follow its camera") end
		ns.SetShotValue(shot, "OrbitBackArc", 70)
		if ns.ShotValue(shot, "OrbitBackArc") ~= 70 then ShotProblem("its own number isn't kept") end
		if ns.CameraValueMode("shot:" .. shot) ~= "vista" then ShotProblem("its row doesn't go by the vista camera") end
		if ns.ShotSetting("vistaOrbitBackArc") ~= ns.GetDB().vistaOrbitBackArc then
			ShotProblem("its number applies while it isn't running")
		end
		local info = ns.ReadCameraShare(ns.ExportCameraTrigger(trigger))
		if not (info and info.source == "emote:wave" and info.shot and info.shot.settings.OrbitBackArc == 70) then
			ShotProblem("a shared trigger doesn't come back whole")
		end
		local tampered = ns.ReadCameraShare(ns.PackCameraShare({ kind = "shot", base = "afk", name = "x|cffff0000",
			settings = { OrbitStep = 9999, Bogus = 1 } }))
		if not (tampered and tampered.settings.OrbitStep == 180 and tampered.settings.Bogus == nil
			and not tampered.name:find("|")) then
			ShotProblem("a tampered shot isn't clamped and cleaned")
		end
		local _, why = ns.ReadCameraShare("CINECAM9:abc")
		if why ~= "newer" then ShotProblem("a newer string reads as " .. tostring(why)) end
		_, why = ns.ReadCameraShare("CINECAM1:{x=s1;}:000000")
		if why ~= "broken" then ShotProblem("a wrong checksum reads as " .. tostring(why)) end
		ns.RemoveShot(shot)
		if ns.CameraRowValue(trigger, "camera") ~= "vista" then ShotProblem("a deleted shot's row isn't back on its camera") end
		ns.RemoveCustomTrigger(trigger)
		ns.ClearTriggerLib() -- (its trigger stays in the library: cleared to look for leftovers)
		local leftover = {}
		for key in pairs(ns.GetDB().cameraRows) do
			-- (The earlier copy's row order; the scenes fixed for this profile.)
			if key ~= "order" and key ~= "scenesFixed" and not tostring(key):find("^scene:") then
				leftover[#leftover + 1] = tostring(key)
			end
		end
		if #leftover > 0 then ShotProblem("left behind: " .. table.concat(leftover, ", ")) end
	end
	-- Visions Style: a Vision's shared setting on "general" follows the Visions
	-- hub's Style page, which follows the Style hub's General; one of its own
	-- wins, and the other pages still follow General alone.
	do
		local db = ns.GetDB()
		local keys = { "styleGeneral", "styleFont", "styleBorder", "styleBorderSize", "visionStyleFont",
			"visionStyleBorder", "visionStyleBorderSize", "visionStyleTextSize", "damageVisionFont",
			"damageVisionTextSize", "tooltipFont", "questItemFrame" }
		local saved = {}
		for _, key in ipairs(keys) do saved[key] = db[key] end
		local look = ns.StyleLook("styleGeneral")
		local function Expect(what, key, want)
			if look[key] ~= want then
				print(("problem\tVisions Style: %s: %s is %s, not %s"):format(what, key, tostring(look[key]), tostring(want)))
			end
		end
		db.styleGeneral, db.styleFont = true, "arial"
		db.visionStyleFont, db.damageVisionFont, db.tooltipFont = "general", "general", "general"
		Expect("both on General", "damageVisionFont", "arial")
		Expect("both on General", "tooltipFont", "arial")
		db.visionStyleFont = "friz"
		Expect("a Visions font", "damageVisionFont", "friz")
		Expect("a Visions font", "tooltipFont", "arial")
		db.visionStyleFont = "game"
		Expect("each Vision's own", "damageVisionFont", ns.SHARED_STYLE.damageVisionFont.own)
		db.damageVisionFont = "morpheus"
		Expect("the Vision's own", "damageVisionFont", "morpheus")
		db.damageVisionTextSize, db.visionStyleTextSize = 1.2, 1.5
		if math.abs((look.damageVisionTextSize or 0) - 1.8) > 1e-6 then
			print("problem\tVisions Style: text size 1.2 x 1.5 is " .. tostring(look.damageVisionTextSize))
		end
		if ns.DEFAULTS.questItemFrame ~= nil then
			db.questItemFrame, db.styleBorder, db.styleBorderSize = "general", "custom", 5
			db.visionStyleBorder = "general"
			Expect("General's custom border", "questItemFrameSize", 5)
			db.visionStyleBorder, db.visionStyleBorderSize = "custom", 3
			Expect("a Visions custom border", "questItemFrame", "custom")
			Expect("a Visions custom border", "questItemFrameSize", 3)
		end
		for _, key in ipairs({ "cardFont", "rollFont", "questTalkFont", "damageVisionTexture" }) do
			local entry = ns.SHARED_STYLE[key]
			if entry and not entry.visions then print("problem\tVisions Style: " .. key .. " isn't marked a Vision's") end
		end
		if ns.SHARED_STYLE.tooltipFont.visions then print("problem\tVisions Style: tooltipFont marked a Vision's") end
		for _, key in ipairs(keys) do db[key] = saved[key] end
	end
	-- Style themes: every setting a theme writes is a real one, a pick shows as
	-- no change of yours, and Undo gives back what was there.
	do
		local themeDb = ns.GetDB()
		local before = {}
		for key, value in pairs(themeDb) do before[key] = value end
		-- (Customize's Theme section: a slot's choice mustn't undo a theme's settings.)
		for _, key in ipairs(ns.StyleThemeSettingKeys()) do
			if ns.SettingSlot(key) then
				print(("problem	Style themes: %s is also the %s slot's"):format(key, ns.SettingSlot(key)))
			end
		end
		for _, info in ipairs(ns.StyleThemeList()) do
			ns.ApplyStyleTheme(info.key)
			if ns.StyleThemeEdited() then print("problem\tStyle theme " .. info.key .. ": shows as edited just after a pick") end
			if themeDb.styleTheme ~= info.key then print("problem\tStyle theme " .. info.key .. ": not picked") end
			ns.UndoStyleTheme()
		end
		for key, value in pairs(before) do
			if themeDb[key] ~= value and type(value) ~= "table" then
				print(("problem\tStyle themes: Undo left %s as %s, not %s"):format(key, tostring(themeDb[key]), tostring(value)))
			end
		end
		for key in pairs(themeDb) do
			if before[key] == nil and themeDb[key] ~= "default" then
				print("problem\tStyle themes: Undo left new setting " .. key)
			end
			if before[key] == nil then themeDb[key] = nil end
		end
		for _, key in ipairs(ns.StyleThemeSettingKeys()) do
			if ns.DEFAULTS[key] == nil and not key:find("^cardLook") then
				print("problem\tStyle themes: no such setting " .. key)
			end
		end
	end
	-- Our own fonts: each path is one the game can read, to a file that's here.
	for _, font in ipairs(ns.QUEST_ITEM_FONTS) do
		if font.own then
			local rest = font[3]:match("^Interface\\AddOns\\[^\\]+\\(.+)$")
			local file = rest and not rest:find("\\\\", 1, true) and io.open((rest:gsub("\\", "/")), "rb")
			if file then
				file:close()
			else
				print("problem	Font " .. font[1] .. ": no file at " .. font[3])
			end
		end
	end
	-- /cine debug themeshots: it runs to the end and leaves the settings as they were.
	do
		local shotDb, timers, shots = ns.GetDB(), {}, 0
		local timer = _G.C_Timer
		local after, screenshot = timer.After, _G.Screenshot
		timer.After = function(_, fn) timers[#timers + 1] = fn end
		_G.Screenshot = function() shots = shots + 1 end
		-- (A stub for a zone's name would loop for ever in a card's letter by letter text.)
		local names = { "GetRealZoneText", "GetZoneText", "GetSubZoneText", "GetMinimapZoneText" }
		for _, name in ipairs(names) do rawset(_G, name, function() return "Darkshore" end) end
		local before = { theme = shotDb.styleTheme, general = shotDb.styleGeneral, texture = shotDb.styleTexture,
			undo = shotDb.styleThemeKept }
		-- (Stuck is a problem to report, not a hang.)
		local chat = ns.Print
		ns.Print = function() end -- (every line printed here counts as a problem)
		debug.sethook(function() error("stuck") end, "", 2000000000)
		local ran, why = pcall(function()
			ns.ThemeShots("")
			while #timers > 0 do table.remove(timers, 1)() end
		end)
		debug.sethook()
		ns.Print = chat
		timer.After, _G.Screenshot = after, screenshot
		for _, name in ipairs(names) do rawset(_G, name, nil) end
		if not ran then print("problem	themeshots: " .. tostring(why)) end
		if shots == 0 then print("problem	themeshots: took no screenshots") end
		if shotDb.themeShotsKept or shotDb.themeShotsCVars then print("problem	themeshots: left its kept settings behind") end
		if shotDb.styleTheme ~= before.theme or shotDb.styleGeneral ~= before.general
			or shotDb.styleTexture ~= before.texture or shotDb.styleThemeKept ~= before.undo then
			print("problem	themeshots: the settings didn't come back")
		end
		shotDb.themeShotsLast = nil
	end
	-- Visions Style: a card left on "default" follows, so nothing shows as its own after a reset.
	do
		local visionDb, keys = ns.GetDB(), { "cardFont", "cardFont_zone", "cardLookFont_third" }
		local kept = {}
		for i, key in ipairs(keys) do kept[i] = visionDb[key] end
		visionDb.cardFont, visionDb.cardFont_zone, visionDb.cardLookFont_third = "general", "default", "default"
		if #ns.VisionOwnKinds(keys) > 0 then print("problem	Visions Style: \"default\" counts as a card's own") end
		visionDb.cardLookFont_third = "bebas"
		if #ns.VisionOwnKinds(keys) ~= 1 then print("problem	Visions Style: a card type's own font doesn't show") end
		for i, key in ipairs(keys) do visionDb[key] = kept[i] end
	end
	-- The Card Types tab's grid: its buttons set their setting, a bar's group shows
	-- with a bar picked, and the gold dots put a change back.
	do
		local kit, made = ns.lowHealthKit, {}
		local page = setmetatable({
			AddControl = function(control)
				made[#made + 1] = control
			end,
			RegisterSubpage = function() end,
			-- (Just this page: other pages' controls need the real game.)
			Refresh = function()
				for _, control in ipairs(made) do control:Refresh() end
			end,
		}, { __index = kit })
		-- (The stand-in's sizes never match what a preview was given: it'd fit itself for ever.)
		local fit = ns.FitStylePreview
		ns.FitStylePreview = function() end
		-- (And a stub for a zone's name would loop for ever: as themeshots, above.)
		local gridZones = { "GetRealZoneText", "GetZoneText", "GetSubZoneText", "GetMinimapZoneText" }
		for _, name in ipairs(gridZones) do rawset(_G, name, function() return "Darkshore" end) end
		ns.CreateCardStylesPanel(page)
		local function Named(name)
			for _, control in ipairs(made) do
				if control.searchLabel == name and control.GetScript and control:GetScript("OnClick") then return control end
			end
			print("problem\tCard grid: no " .. name .. " button")
		end
		local function Click(control) if control then control:GetScript("OnClick")(control) end end
		local function Field(field, want, doing)
			local value = ns.CardStyleRaw("third", field)
			if value ~= want then
				print(("problem\tCard grid: %s: %s is %s, not %s"):format(doing, field, tostring(value), tostring(want)))
			end
		end
		page.Refresh()
		local left = Named("Left")
		local wasStyle, wasPlace = ns.CardStyleRaw("third", "Style"), ns.CardStyleRaw("third", "Place")
		if left and left:IsShown() then print("problem\tCard grid: a bar's group shows with no bar") end
		Click(Named("Banner"))
		Field("Style", "banner", "clicking Banner")
		Click(Named("Top bar"))
		Field("Place", "top", "clicking Top bar")
		if left and left:IsShown() then print("problem\tCard grid: a bar's group shows on a banner") end
		Click(Named("Title"))
		if left and not left:IsShown() then print("problem\tCard grid: a bar's group doesn't show with a bar") end
		local dots = 0
		for _, control in ipairs(made) do
			if control.searchSkip and control:IsShown() and control.GetScript and control:GetScript("OnClick") then
				dots = dots + 1
				Click(control)
			end
		end
		if dots ~= 2 then print("problem\tCard grid: " .. dots .. " dots for 2 changes") end
		Field("Style", wasStyle, "its dot")
		Field("Place", wasPlace, "its dot")
		ns.FitStylePreview = fit
		for _, name in ipairs(gridZones) do rawset(_G, name, nil) end
	end
	-- A lower third card moves up clear of a chat window you can see, and only then.
	do
		local chatDb = ns.GetDB()
		local wasClear, wasSecret = chatDb.cardClearChat, rawget(_G, "issecretvalue")
		local stage = CreateFrame("Frame", nil, UIParent)
		local look = setmetatable({ combatPlace = "third", combatStyle = "chapter" }, { __index = ns.CardLook("zone") })
		local card = { name = "Kharanos", sub = "Dun Morogh" }
		ns.PlayCard(stage, look, 1000, 600, 1, card)
		local cue = stage.cue
		-- (Text 100-300 across, the sub line under it down to 120; chat's top at 140, its tabs to 165.)
		local function Place(part, left, right, bottom, top)
			function part:GetLeft() return left end
			function part:GetRight() return right end
			function part:GetBottom() return bottom end
			function part:GetTop() return top end
		end
		Place(cue.text, 100, 300, 150, 190)
		Place(cue.sub, 100, 220, 120, 140)
		Place(cue.line, 100, 100, 145, 146)
		local chat, tab = CreateFrame("Frame"), CreateFrame("Frame")
		local function Lift(place, scale)
			rawset(_G, "ChatFrame1", chat)
			rawset(_G, "ChatFrame1Tab", tab)
			chat:Show()
			tab:Show()
			Place(chat, 30, 460, 20, 140)
			Place(tab, 30, 110, 140, 165)
			function chat:GetEffectiveAlpha() return 1 end
			function tab:GetEffectiveAlpha() return 1 end
			if place then place() end
			ns.PlayCard(stage, look, 1000, 600, scale or 1, card)
			ns.SetOnUpdate(stage, nil)
			rawset(_G, "ChatFrame1", nil)
			rawset(_G, "ChatFrame1Tab", nil)
			rawset(_G, "issecretvalue", wasSecret)
			return cue.chatLift
		end
		local function Expect(name, want, place, scale)
			local lift = Lift(place, scale)
			if math.abs(lift - want) > 1e-6 then
				print(("problem\tCard clear of chat: %s lifted %s, not %s"):format(name, tostring(lift), tostring(want)))
			end
		end
		chatDb.cardClearChat = true
		Expect("a card on the chat and its tabs", 55) -- (bottom 120 to tabs' 165 + 10)
		Expect("a window's faded tabs", 55, function()
			function tab:GetEffectiveAlpha() return 0 end
		end)
		Expect("a faded window and its tabs", 0, function()
			function chat:GetEffectiveAlpha() return 0 end
			function tab:GetEffectiveAlpha() return 0 end
		end)
		Expect("a chat window hidden", 0, function() chat:Hide(); tab:Hide() end)
		Expect("a faded chat window", 0, function()
			function chat:GetEffectiveAlpha() return 0 end
			tab:Hide()
		end)
		Expect("a chat window elsewhere", 0, function() Place(chat, 700, 900, 20, 140); tab:Hide() end)
		Expect("a chat window too tall to clear", 0, function() Place(chat, 30, 460, 20, 500); tab:Hide() end)
		Expect("a secret chat place", 0, function()
			rawset(_G, "issecretvalue", function(value) return value == 140 or value == 165 end)
		end)
		Expect("a preview", 0, nil, 0.3)
		look.combatPlace, look.combatBarFallback = "top", "bar"
		Expect("a card in a letterbox bar", 0)
		look.combatPlace = "third"
		chatDb.cardClearChat = false
		Expect("the option off", 0)
		chatDb.cardClearChat = true
		-- (/cine debug cardchat runs. A stub for a zone's name would loop for ever: as themeshots, above.)
		local chatPrint = ns.Print
		ns.Print = function() end
		local zoneNames = { "GetRealZoneText", "GetZoneText", "GetSubZoneText", "GetMinimapZoneText" }
		for _, name in ipairs(zoneNames) do rawset(_G, name, function() return "Darkshore" end) end
		rawset(_G, "ChatFrame1", chat)
		local ran, why = pcall(ns.CardChatTest)
		rawset(_G, "ChatFrame1", nil)
		for _, name in ipairs(zoneNames) do rawset(_G, name, nil) end
		ns.Print = chatPrint
		ns.Cards.Cut("zone")
		if not ran then print("problem\tCard clear of chat: /cine debug cardchat: " .. tostring(why)) end
		chatDb.cardClearChat = wasClear
	end
	-- The Show in tables' CineMode column: its tick shows the row in CineMode
	-- only, and reads as the rule word both ways. And the Toggle CineMode key
	-- with Start in CineMode off: it starts CineMode, then stops it, no snooze.
	do
		local cineDb, key = ns.GetDB(), "effect:letterbox"
		local wasTick = cineDb.cineModeShow[key]
		cineDb.cineModeShow[key] = true
		if ns.RuleShows(key, { cinemode = true }) ~= true or ns.RuleShows(key, { cinemode = false }) ~= nil then
			print("problem\tCineMode column: its tick doesn't show the row in CineMode only")
		end
		if not ns.RowTicksRule(key):find("cinemode") then
			print("problem\tCineMode column: its tick isn't in the row's ticks as a rule")
		end
		cineDb.cineModeShow[key] = wasTick
		local always, ticked = ns.ReadGridRule("cinemode or combat", { cinemode = true, combat = true })
		if always ~= false or not ticked.cinemode then
			print("problem\tCineMode column: a rule of its word doesn't go back into the column")
		end
		local wasFade, wasEnabled, wasChosen, wasPrint = cineDb.fadeUI, cineDb.enabled, ns.ProfileChosen, ns.Print
		cineDb.fadeUI, cineDb.enabled = false, true
		ns.ProfileChosen, ns.Print = function() return true end, function() end
		Cinematic_ToggleCineMode()
		if not ns.cineKeyOn or ns.GetSnoozeLeft() then
			print("problem\tToggle CineMode with Start in CineMode off: the key doesn't start it")
		end
		Cinematic_ToggleCineMode()
		if ns.cineKeyOn or ns.GetSnoozeLeft() then
			print("problem\tToggle CineMode with Start in CineMode off: the key doesn't stop it, or snoozes")
		end
		cineDb.fadeUI, cineDb.enabled, ns.ProfileChosen, ns.Print = wasFade, wasEnabled, wasChosen, wasPrint
		-- Subtle's bars moved over: off ones only, and Always or a rule left alone.
		local moved = { letterbox = false, quietShow = { [key] = true } }
		ns.SubtleCineBars(moved)
		if moved.letterbox ~= true or not moved.cineModeShow[key] or moved.quietShow[key] ~= false then
			print("problem	Subtle's bars: an old Subtle isn't moved onto the Cine tick")
		end
		local mine = { letterbox = false, letterboxAlways = true }
		ns.SubtleCineBars(mine)
		local ruled = { letterbox = false, frameRules = { [key] = "city" } }
		ns.SubtleCineBars(ruled)
		local on = { letterbox = true }
		ns.SubtleCineBars(on)
		if mine.letterbox ~= false or ruled.letterbox ~= false or on.cineModeShow then
			print("problem	Subtle's bars: settings of the player's own were changed")
		end
		-- Subtle's tint and the old strengths, the same way.
		local tint = { tintAlways = true, tintStrength = 0.33 }
		ns.SubtleCineEffect(tint, "tint")
		ns.FullTint(tint)
		local ownTint = { tintAlways = false, tintStrength = 0.5 }
		ns.SubtleCineEffect(ownTint, "tint")
		ns.FullTint(ownTint)
		if tint.tintAlways ~= false or not tint.cineModeShow["effect:tint"] or tint.tintStrength ~= 1
			or ownTint.cineModeShow or ownTint.tintStrength ~= 0.5 then
			print("problem	Subtle's tint or the tint's strength wasn't moved over as it should be")
		end
		-- Subtle's flights, teleports and AFK moved onto CineMode: the Never choice
		-- and an AFK camera of the player's own left alone.
		local travel = { eventAFKCamera = "none" }
		ns.SubtleCineTravel(travel)
		local never = { eventAFKCamera = "none", eventFlightCamera = "none", eventHearthCamera = "none" }
		ns.SubtleCineTravel(never)
		local ownAFK = { eventAFKCamera = "cozy" }
		ns.SubtleCineTravel(ownAFK)
		if travel.eventAFKCamera ~= "afk" or not travel.eventFlightCine or not travel.eventAFKCine
			or never.eventAFKCine or never.eventAFKCamera ~= "none" or ownAFK.eventAFKCine then
			print("problem	Subtle's flights, teleports and AFK weren't moved onto CineMode as they should be")
		end
		local subtle = ns.ProfileBase("Subtle")
		if subtle.eventAFKCamera ~= "afk" or subtle.deathCine then
			print("problem	Subtle: going AFK has no camera, or dying brings CineMode")
		end
		for _, event in ipairs({ "Flight", "Hearth", "Teleport", "AFK" }) do
			if not subtle["event" .. event .. "Cine"] then
				print("problem	Subtle: " .. event .. " doesn't bring CineMode on")
			end
		end
		-- (The effects only show in CineMode now: Subtle's are on all through it,
		-- their rows' Always, with no CineMode tick left over.)
		for _, effect in ipairs(ns.EFFECT_GRID) do
			local row = "effect:" .. effect
			if not subtle[effect .. "Always"] or (subtle.cineModeShow and subtle.cineModeShow[row]) then
				print("problem	Subtle's " .. effect .. " isn't on all through CineMode")
			end
		end
		-- The effects' old CineMode ticks go onto Always, once.
		local old = { cineModeShow = { ["effect:letterbox"] = true, ["effect:tint"] = false }, tintAlways = false }
		ns.EffectCineTicksToAlways(old)
		if not old.letterboxAlways or old.tintAlways ~= false or next(old.cineModeShow) ~= nil then
			print("problem	Effects' CineMode ticks weren't moved onto Always as they should be")
		end
		-- The Calm Timer after a fight is the fight still: a row shows then as
		-- its In combat tick says.
		do
			local calmDb = ns.GetDB()
			local was = calmDb.combatShow["effect:letterbox"]
			calmDb.combatShow["effect:letterbox"] = true
			local on = ns.IsCalmShowOn("effect:letterbox")
			calmDb.combatShow["effect:letterbox"] = false
			local off = ns.IsCalmShowOn("effect:letterbox")
			calmDb.combatShow["effect:letterbox"] = was
			if not on or off then
				print("problem	Calm Timer: a row doesn't go by its In combat tick after a fight")
			end
		end
	end
	-- A flight's CineMode tick, with the flight camera playing as its script:
	-- its own code is off then, and the tick still counts. Stop camera ends it.
	do
		local db = ns.GetDB()
		local cine, camera = db.eventFlightCine, db.eventFlightCamera
		local function Starts(tick, stopped)
			db.eventFlightCine, db.eventFlightCamera, ns.stoppedCam = tick, "flight", stopped
			ns.CameraRowsChanged()
			return ns.TriggerStartsCine() and true or false
		end
		-- (Each ask a frame of its own: on a flight or not is kept for the frame.)
		local keptTime, clock = rawget(_G, "GetTime"), 100
		_G.GetTime = function() clock = clock + 0.001 return clock end
		ns.testTravel = "flight"
		ns.UpdateTaxi()
		if not ns.CameraRowsScripted("flight") then print("problem	the flight camera isn't playing as its script") end
		if not Starts(true) then print("problem	a flight's CineMode tick doesn't bring CineMode on") end
		if Starts(false) or Starts(true, "flight") then
			print("problem	a flight brings CineMode on unticked, or with its camera stopped")
		end
		ns.testTravel, ns.stoppedCam = nil, nil
		ns.UpdateTaxi()
		_G.GetTime = keptTime
		db.eventFlightCine, db.eventFlightCamera = cine, camera
		ns.CameraRowsChanged()
		-- The same for walking and running, and what goes with a quest giver's
		-- or a conversation's camera, played as a script.
		for _, cam in ipairs({ "walk", "run" }) do
			local was, wait, always = db[cam .. "Camera"], db[cam .. "CameraDelay"], db["camAlways" .. cam]
			local offKey = "sceneOff" .. (cam == "walk" and "Walk" or "Run")
			local off = db[offKey]
			db[cam .. "Camera"], db[cam .. "CameraDelay"], db["camAlways" .. cam], db[offKey] = cam, 0, true, false
			ns.CameraRowsChanged()
			if not ns.CameraPlaysHere(cam) then print("problem	the " .. cam .. " camera doesn't count as playing as its script") end
			db[offKey] = true
			ns.CameraRowsChanged()
			if ns.CameraPlaysHere(cam) then print("problem	the " .. cam .. " camera plays with its scene ticked off") end
			db[cam .. "Camera"], db[cam .. "CameraDelay"], db["camAlways" .. cam], db[offKey] = was, wait, always, off
		end
		local running, immersive = ns.CameraScriptRunning, db.chatCamImmersive
		ns.CameraScriptRunning = function() return true end
		if not ns.QuestCamActive() then print("problem	a quest giver's script doesn't count as the quest camera") end
		ns.CameraScriptRunning = function(key) return key == "Chat" end
		db.chatCamImmersive = true
		if ns.ChatCamScene() ~= "Chat" or not ns.ChatCamActive() or not ns.ChatCamImmersive() then
			print("problem	a conversation's script doesn't count as the chat camera")
		end
		ns.CameraScriptRunning, db.chatCamImmersive = running, immersive
		ns.CameraRowsChanged()
	end
	-- Vitals Vision: a page's Reset (its settings back to the profile's) leaves
	-- each theme's own look on them, not the plain defaults.
	local db, base = ns.GetDB(), ns.ProfileBase()
	for _, theme in ipairs(ns.LOW_HEALTH_THEMES) do
		db.lowHealthTheme = theme.key
		ns.ResyncVitalsLook()
		for key in pairs(theme.look or {}) do db[key] = base[key] end
		ns.ResyncVitalsLook()
		for key, value in pairs(theme.look or {}) do
			if db[key] ~= value then
				print(("problem\tVitals theme %s: %s after a Reset is %s, not its %s"):format(theme.key, key,
					tostring(db[key]), tostring(value)))
			end
		end
		-- (Its look is the theme's, not a change: no "(changed)" on the Profiles
		-- page. The profile's base given this theme, as picking it is a change.)
		local baseTheme = base.lowHealthTheme
		base.lowHealthTheme = theme.key
		if ns.ProfileChanged() then
			local fromTheme = db.lowHealthFromTheme and db.lowHealthFromTheme.values or {}
			local diff = {}
			for k in pairs(ns.DEFAULTS) do
				if ns.IsProfileKey(k) and db[k] ~= base[k] and fromTheme[k] ~= db[k] then diff[#diff + 1] = k end
			end
			table.sort(diff)
			print(("problem\tVitals theme %s: the profile shows (changed): %s"):format(theme.key, table.concat(diff, ", ")))
		end
		base.lowHealthTheme = baseTheme
	end
	-- A player on a built-in that's gone keeps their settings as a profile of
	-- their own, and one they're not on is deleted. (Last: it changes profile.)
	db.liveProfile, db.profile, db.tintStrength = "Camera Only", "Camera Only", 0.4
	db.profiles["Solo Explorer"] = { tintStrength = 0.2 }
	ns.InitProfiles()
	if db.profiles["Solo Explorer"] then
		print("problem\tOld built-ins: one you're not on is still saved")
	end
	-- (Twice: the next login mustn't take what was kept for the old built-in.)
	for _ = 1, 2 do
		if ns.ActiveProfile() ~= "Camera Only" or not db.profiles["Camera Only"] or db.tintStrength ~= 0.4
			or db.profiles["Camera Only"].tintStrength ~= 0.4 then
			print("problem\tOld built-ins: the one you're on isn't kept as a profile of your own, as it was")
		end
		ns.InitProfiles()
	end
	return
end

local problems, seen, notes = {}, {}, {}
local function Problem(text)
	if not seen[text] then
		seen[text] = true
		problems[#problems + 1] = text
	end
end
local looked, absent, nowhere, used, settings = {}, {}, {}, {}, { forever = {}, retail = {} }
for _, run in ipairs(RUNS) do
	local where = run[1] .. " (" .. run[2] .. ")"
	local pipe = io.popen(("%s Tools/offline/check.lua %s %s 2>&1"):format(LUA, run[1], run[2]))
	for line in pipe:lines() do
		local kind, a, b = line:match("^(%a+)\t([^\t]*)\t?(.*)$")
		if kind == "problem" then
			Problem(where .. ": " .. a)
		elseif kind == "note" then
			if not seen["note " .. a] then
				seen["note " .. a] = true
				notes[#notes + 1] = a
			end
		elseif kind == "absent" then
			absent[a .. "\t" .. b] = (absent[a .. "\t" .. b] or 0) + 1
		elseif kind == "nowhere" then
			nowhere[a .. "\t" .. b] = (nowhere[a .. "\t" .. b] or 0) + 1
		elseif kind == "module" then
			looked[a] = (looked[a] or 0) + 1
		elseif kind == "used" then
			used[a] = true
		elseif kind == "settings" then
			table.insert(settings[run[1]], a)
		else
			Problem(where .. ": " .. line)
		end
	end
	pipe:close()
end
-- (A scope entry missing on every run its module was on: on neither client.)
for pair, count in pairs(absent) do
	local key, entry = pair:match("^(.-)\t(.*)$")
	if count >= looked[key] then
		Problem(("module %s: its scope's %s isn't on either client's options"):format(key, entry))
	end
end
-- (A setting a module writes on no page on every run: on neither client.)
for pair, count in pairs(nowhere) do
	local key, setting = pair:match("^(.-)\t(.*)$")
	if count >= looked[key] then
		Problem(("module %s: %s isn't on either client's options"):format(key, setting))
	end
end
for key in pairs(looked) do
	if not used[key] then Problem(("module %s: no built-in profile or part uses it"):format(key)) end
end

-- The built-ins' settings against the saved ones (or saved, with --update).
for client, lines in pairs(settings) do
	table.sort(lines)
	local path = "Tools/offline/profile-settings-" .. client .. ".txt"
	if update then
		local file = assert(io.open(path, "wb"))
		file:write(table.concat(lines, "\n"), "\n")
		file:close()
		print(("saved %d settings to %s"):format(#lines, path))
	else
		local saved, now = {}, {}
		local file = io.open(path, "rb")
		if not file then
			Problem(path .. " isn't there: run with --update to make it")
		else
			for line in file:lines() do
				line = line:gsub("\r$", "")
				if line ~= "" then saved[line] = true end
			end
			file:close()
			for _, line in ipairs(lines) do now[line] = true end
			local changed = {}
			for line in pairs(saved) do
				if not now[line] then changed[#changed + 1] = "  was " .. line end
			end
			for _, line in ipairs(lines) do
				if not saved[line] then changed[#changed + 1] = "  now " .. line end
			end
			if #changed > 0 then
				table.sort(changed, function(x, y) return x:sub(7) < y:sub(7) end)
				Problem(("%s: built-in profiles' settings changed (if that's meant, run with --update):\n%s")
					:format(client, table.concat(changed, "\n")))
			end
		end
	end
end

table.sort(problems)
table.sort(notes)
for _, line in ipairs(problems) do print(line) end
for _, line in ipairs(notes) do print("note: " .. line) end
print(("profile modules: %d problems, %d notes"):format(#problems, #notes))
os.exit(#problems == 0 and 0 or 1)
