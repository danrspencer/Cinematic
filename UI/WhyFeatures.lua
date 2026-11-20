-- The Why window's tabs beyond the frames (WhyPanel.lua's ns.WhyProvider):
-- Cameras (the one playing and the triggers on now, in their order; the
-- standing-still timer and what holds it; each camera, playing, ready, held
-- or off and why) and Cards (the one on screen and those waiting; each
-- card, ready or why not, and what it last did) and Visions (each Vision and
-- Atmosphere page and its tabs, by their switches, and what each is doing
-- where it can tell). And what goes on Recent as
-- it happens: a camera starting or stopping (the director, ns.WhyCameraChanged).
-- (Cards.lua notes its own cards' moments; Triggers' log its held-back ones.)

local _, ns = ...
local L = ns.L

local function R(state, text, page, setting)
	return { state = state, text = text, page = page, setting = setting }
end
-- A hub's pages as rows (below; the Cameras tab asks for the Camera hub's).
local HubSection

-- Cameras ---------------------------------------------------------------

-- When each camera of the Cameras page's list plays.
local CAM_WHEN = {
	flight = "Plays on a flight path", idle = "Plays once you've stood still long enough",
	cozy = "Plays when a scene picks it: a drawn weapon, a campfire...", tele = "Plays when a scene picks it: a teleport cast",
	vista = "Plays when a scene picks it: an emote, a seat...", fish = "Plays while you fish",
	walk = "Plays while you auto-walk", run = "Plays while you auto-run", death = "Plays when you die",
	quest = "Plays when you talk to a quest giver", chatcam = "Plays when NPCs talk to you",
}
-- Those that play only in CineMode (DecideScene's ns.activeCam).
local NEEDS_CINE = { flight = true, idle = true, cozy = true, tele = true, vista = true, fish = true, walk = true, run = true }
-- What holds the standing-still timer (DecideScene's ns.stillPausedBy).
local PAUSED = {
	taxi = "You're on a flight", active = "You're moving or doing something",
	npc = "An NPC's window is open", window = "A menu or game window is open (Scenes page: Pause in windows)",
	movie = "A movie or cutscene is playing", casting = "You're casting",
	chat = "Chat Cam is playing (NPCs talking to you)",
}

local function CamName(cam)
	if cam == "idle" then return ns.CAMERA_NAMES.afk end
	if cam == "chatcam" then return ns.CAMERA_NAMES.chat end
	return (ns.CameraName and ns.CameraName(cam)) or ns.CAMERA_NAMES[cam] or tostring(cam)
end

-- Why a camera is playing, in words.
local function CamReason(cam)
	if cam == "flight" then return L["You're on a flight path"] end
	if cam == "walk" then return L["You're auto-walking"] end
	if cam == "run" then return L["You're auto-running"] end
	if cam == "quest" then return L["A quest giver is talking to you"] end
	if cam == "chatcam" then return L["NPCs are talking to you"] end
	if cam == "death" then return L["You died"] end
	if cam == "idle" and not ns.ActiveEvent() then
		return L["You've stood still for %d sec"]:format(ns.stillSince and GetTime() - ns.stillSince or 0)
	end
	local key = ns.ActiveEvent()
	if key then
		-- (Its scene's name alone: ns.CameraEventDetail's words are for the
		-- debug log, "SIT via PerformEmote, 0 sec ago".)
		local name = ns.SceneDisplayName and ns.SceneDisplayName(key) or tostring(key)
		return L["Scene: %s"]:format(name)
	end
	return L["A camera script is playing"]
end

-- The triggers on now, in their order, from the last pick (Triggers.lua).
local function TriggerLines(out)
	local seen = ns.triggerPickSeen
	if not seen or GetTime() - seen.at > 1 then
		out[#out + 1] = R("off", L["Triggers aren't being looked at right now: you're moving, a window is open, " ..
			"or a camera was started by hand"], "Trigger Priority")
		return
	end
	if seen.n == 0 then
		out[#out + 1] = R("off", L["No trigger is on right now"], "Trigger Priority")
		return
	end
	for i = 1, seen.n do
		local each = seen[i]
		local source = each.source
		local label = source.label or (ns.BUILT_IN_SOURCE_NAMES and ns.BUILT_IN_SOURCE_NAMES[source.id])
		label = label and L[label] or tostring(source.id)
		local scene = ns.SceneDisplayName and ns.SceneDisplayName(each.key) or tostring(each.key)
		local text
		if each.key == seen.won and each.camera then
			out[#out + 1] = R("on", L["%d. %s: %s, wins (%s)"]:format(i, label, scene, CamName(each.camera)), "Trigger Priority")
		else
			if not each.camera then
				text = L["%d. %s: %s, no camera set for it here"]:format(i, label, scene)
			elseif not each.ok then
				text = L["%d. %s: %s, held back by its own settings (see the Trigger Log)"]:format(i, label, scene)
			else
				text = L["%d. %s: %s, has a camera but ranks lower"]:format(i, label, scene)
			end
			out[#out + 1] = R("off", text, each.ok == false and each.camera and "Trigger Log" or "Trigger Priority")
		end
	end
end

local function CameraNow()
	local cam = ns.activeCam
	local reasons = {}
	if cam then
		reasons[1] = R("on", L["%s: %s"]:format(CamName(cam), CamReason(cam)), "Cameras")
	end
	-- (What stops them first, so the line under the row says it.)
	if ns.db and ns.db.cameraModes == false then
		reasons[#reasons + 1] = R("block", L["Enable Cameras is off"], "Cameras")
	end
	if not ns.lastCinematic then
		reasons[#reasons + 1] = R("block", L["CineMode is off: only the death, quest and Chat cameras play without it"],
			"CineMode")
	end
	if not cam then reasons[#reasons + 1] = R("off", L["No camera is playing"], "Cameras") end
	TriggerLines(reasons)
	return { key = "cam:now", title = L["Camera now"], status = cam and "on" or "idle",
		label = cam and L["PLAYING"] or L["NONE"], reasons = reasons, settingsPage = "Cameras",
		right = cam and CamName(cam) or nil }
end

local function StillTimer()
	local db = ns.db or {}
	local delay = db.idleOrbitDelay or 0
	local reasons, status, label, right = {}, "idle", nil, nil
	local paused = ns.stillPausedBy
	if paused then
		status, label = "held", L["PAUSED"]
		reasons[1] = R("block", L[PAUSED[paused] or "Something you're doing"])
	elseif ns.stillSince then
		local still = GetTime() - ns.stillSince
		right = ("%d / %d"):format(math.min(still, delay), delay)
		if still < delay then
			status, label = "ready", L["RUNNING"]
			reasons[1] = R("on", L["You've stood still %d of %d sec"]:format(still, delay), "Scenes", "idleOrbitDelay")
		else
			status, label = "on", L["RUN OUT"]
			reasons[1] = R("on", L["You've stood still %d sec, past its %d"]:format(still, delay), "Scenes", "idleOrbitDelay")
			if ns.activeCam == "idle" then
				reasons[#reasons + 1] = R("on", L["So the AFK camera is playing"], "Cameras")
			elseif db.idleOrbit == false then
				reasons[#reasons + 1] = R("block", L["The AFK camera is off"], "Cameras")
			elseif ns.IsCameraOffHere("idle") then
				reasons[#reasons + 1] = R("block", L["The AFK camera is off here: %s"]:format(
					L[ns.CameraOffWhy("idle") or "no row plays it"]), "Scenes")
			elseif not ns.StillRunsAFK() then
				reasons[#reasons + 1] = R("block", L["Stand still is set to another camera or none"], "Scenes")
			end
		end
	else
		reasons[1] = R("off", L["It starts as you stop"], "Scenes", "idleOrbitDelay")
	end
	reasons[#reasons + 1] = R("off", L["It runs while you stand still and nothing holds it: no flight, NPC or menu " ..
		"window, cast or cutscene"])
	return { key = "cam:still", title = L["Standing-still timer"], status = status, label = label, reasons = reasons,
		main = reasons[1], settingsPage = "Scenes", right = right }
end

local function CameraRow(cam, label)
	local reasons, status, word = {}, "ready", nil
	if ns.activeCam == cam then
		status, word = "on", L["PLAYING"]
		reasons[1] = R("on", CamReason(cam), "Cameras")
	elseif ns.CameraOffBesidesRows(cam) then
		status = "off"
		reasons[1] = R("block", L[ns.CameraOffWhy(cam) or "Off here"], "Cameras")
	elseif ns.CameraRowsOff(cam) then
		status = "off"
		reasons[1] = R("block", L["No row on the Scenes page plays it here and now"], "Scenes")
	elseif NEEDS_CINE[cam] and not ns.lastCinematic then
		status = "held"
		reasons[1] = R("block", L["It plays only while CineMode is on"], "CineMode")
	else
		reasons[1] = R("on", L[CAM_WHEN[cam] or "Ready"], "Scenes")
	end
	if status ~= "on" and CAM_WHEN[cam] and status ~= "ready" then
		reasons[#reasons + 1] = R("off", L[CAM_WHEN[cam]])
	end
	local last = ns.WhyLastMoment and ns.WhyLastMoment("cam:" .. cam)
	if last then
		reasons[#reasons + 1] = R("off", L["Last: %s, %s"]:format(last.outcome, ns.WhyAgo(last.at)))
	end
	return { key = "cam:" .. cam, title = CamName(cam) or label, status = status, label = word, reasons = reasons,
		main = reasons[1], settingsPage = "Cameras" }
end

ns.WhyProvider("cameras", "Cameras", "The camera playing now, and every trigger that's on, in order: the first one with a camera " ..
	"wins. Below that, each camera says whether it's playing, ready, or why it's off.", function()
	local rows = {}
	for _, each in ipairs(ns.CAMERA_OFF_CAMS) do
		local ok, row = pcall(CameraRow, each[1], each[2])
		if ok then rows[#rows + 1] = row end
	end
	return {
		{ label = "Right now", rows = { CameraNow(), StillTimer() }, keepOrder = true },
		{ label = "Cameras", rows = rows },
		-- (The Camera hub's pages by their switches: Scenes, Triggers, Skyriding Cam...)
		HubSection("Camera", "Camera pages"),
	}
end)

-- A camera started or stopped (the director, Director.lua): on Recent.
function ns.WhyCameraChanged(before, after)
	if not ns.WhyMoment then return end
	if before then
		local why = (not ns.lastCinematic and NEEDS_CINE[before] and L["CineMode turned off"])
			or (ns.playerMoving and L["You moved"])
			or (ns.stillPausedBy and L[PAUSED[ns.stillPausedBy] or "Something you did"])
			or L["What started it is over"]
		if after then why = L["%s took over"]:format(CamName(after)) end
		ns.WhyMoment("camera", "cam:" .. before, CamName(before), L["stopped"], "idle", why, "Cameras")
	end
	if after then
		ns.WhyMoment("camera", "cam:" .. after, CamName(after), L["started"], "on", CamReason(after), "Cameras")
	end
end

-- Visions and Atmosphere ------------------------------------------------
-- Each icon of the two hubs (ns.HubIcons: their order, labels and switches)
-- and its tabs under it (ns.PageTabsOf), as the switch tree has them: off by
-- its own switch or one it's under; else doing it now where the feature can
-- tell (NOW), else ready for its moment (WHEN).

local NOW = {
	["Vitals Vision"] = function()
		return ns.VitalsVisionActive and ns.VitalsVisionActive() and L["Your health is low: the screen's edges show it"]
	end,
	["Heal Vision"] = function()
		return ns.HealVisionActive and ns.HealVisionActive() and L["It's handling your group's frames"]
	end,
	["Emote Vision"] = function()
		return ns.EmoteCardShown and ns.EmoteCardShown() and L["An emote card is up"]
	end,
	["Quest Vision"] = function()
		return ns.QuestTalkNow and ns.QuestTalkNow() and L["A quest giver is talking to you"]
	end,
	["Letterbox"] = function()
		return ns.LetterboxUp and ns.LetterboxUp() and L["The black bars are up"]
	end,
	["Teleport Vision"] = function()
		return ns.TeleportVisionShown and ns.TeleportVisionShown() and L["A Hearthstone or teleport cast: the portal is up"]
	end,
	-- (By their own frames being up.)
	["Damage Vision"] = function()
		-- (Up and not faded out: it stays shown for a moment as it fades.)
		local function Up(each) return each and each:IsVisible() and each:GetEffectiveAlpha() > 0.05 end
		return (Up(_G.CinematicDamageVision) or Up(_G.CinematicDamageRecap)) and L["Its damage meter is up"]
	end,
	["Roll Vision"] = function()
		local rolls = _G.CinematicRolls
		return rolls and rolls:IsVisible() and L["Its roll window is up"]
	end,
	["Card Vision"] = function()
		local current = ns.Cards and ns.Cards.Queue()
		local event = current and ns.CARD_BY_ID and ns.CARD_BY_ID[current.id]
		return event and L["On screen: %s"]:format(L[event.name])
	end,
}
-- What each waits for, while on and not doing it now.
local WHEN = {
	["Vitals Vision"] = "Shows as your health gets low", ["Heal Vision"] = "Works on your group's frames while you're in a group",
	["Damage Vision"] = "Shows in fights", ["Quest Vision"] = "Shows as you talk to quest givers and near quest mobs",
	["Roll Vision"] = "Shows as loot is rolled for", ["Duel Vision"] = "Shows in duels",
	["Death Vision"] = "Shows while you're dead, with the death camera",
	["Teleport Vision"] = "Shows as you teleport or use a Hearthstone",
	["Emote Vision"] = "Shows a card when someone emotes at you or another of its moments happens",
	["Card Vision"] = "Each card is on the Cards tab", ["Tint"] = "Tints the world by the time of day and where you are",
	["Letterbox"] = "Black bars at the top and bottom of the screen in CineMode",
	["Graphics+"] = "Raises the game's graphics where it can", ["Audio"] = "Music and sounds for CineMode",
	-- (The Camera hub's.)
	["Scenes"] = "Picks the camera for each moment",
	["Triggers"] = "Your own moments for the scenes", ["Camera Scripts"] = "Cameras played as scripts",
	["My Shots"] = "Your own camera shots, for the scenes to pick", ["Skyriding Cam"] = "Plays while you skyride",
	["Shoulder Cam"] = "An over-the-shoulder camera while you move",
	-- (Quality of Life's and the Wheels'.)
	["Fishing"] = "Helps while you fish",
	["Hunter"] = "Hunter helpers: pets, ammo...", ["Keyboard Map"] = "Your key bindings on a keyboard; drag spells onto it to bind them",
	["Master wheel"] = "Opens every wheel from one key", ["Your wheels"] = "Wheels you made",
	["Camera wheel"] = "Starts a camera from a wheel", ["Menu wheel"] = "The game's menus on a wheel",
	["Marker wheel"] = "Raid markers on a wheel", ["Ground marker wheel"] = "Ground markers on a wheel",
	["Vision wheel"] = "Visions on a wheel",
}
-- Pages listed as tabs of a page that aren't on its row of tabs (a card's
-- own pages, opened from its row): left out.
local NOT_TABS = { ["Card Settings"] = true, ["Card Style"] = true, ["Card Sounds"] = true }
-- A tab's name as its folder tab has it: its label, else its page's name
-- without its parent's ("Emote Vision Settings": Settings).
local function TabTitle(tab, parent)
	local name = tostring(tab.name)
	if name:sub(1, #parent + 1) == parent .. " " and (tab.label == L[name] or #tab.label > 24) then
		return L[name:sub(#parent + 2)]
	end
	return tab.label
end

local function SwitchRow(state, title, page, when, now, parentOff)
	local reasons, status = {}, "ready"
	if parentOff then
		status = "off"
		reasons[1] = R("block", L["Its page is off"], page)
	elseif state.on == false then
		status = "off"
		reasons[1] = R("block", state.held and L["It's on, but a switch it's under is off"]
			or L["Its Enable Page switch is off"], page)
	elseif now then
		status = "on"
		reasons[1] = R("on", now, page)
	else
		reasons[1] = R("on", when and L[when] or L["On"], page)
	end
	if when and reasons[1].text ~= L[when] then reasons[#reasons + 1] = R("off", L[when]) end
	return { key = "page:" .. tostring(state.name), title = title, status = status, reasons = reasons,
		main = reasons[1], settingsPage = page }
end

-- (A hub's General page left out: its switch is over the others, so when
-- it's off each of them says so, and on it's nothing to explain.)
local function Listed(icon)
	return not icon.dev and icon.label ~= L["General"]
end
function HubSection(hubName, label)
	local rows = {}
	for _, icon in ipairs(ns.HubIcons and ns.HubIcons(hubName) or {}) do
		if Listed(icon) then
			local okNow, now = pcall(NOW[icon.name] or tostring, nil)
			now = okNow and NOW[icon.name] and now or nil
			local row = SwitchRow(icon, icon.label, icon.name, WHEN[icon.name], now)
			-- (Its tabs with a page of their own, each under it.)
			local tabs = ns.PageTabsOf and ns.PageTabsOf(icon.name) or {}
			if #tabs > 0 then
				row.parts, row.partsLabel = {}, L["%d tabs"]
				for _, tab in ipairs(tabs) do
					if not NOT_TABS[tab.name] then
						local part = SwitchRow(tab, TabTitle(tab, icon.name), tab.name, nil, nil, row.status == "off")
						if tab.on == nil and row.status ~= "off" then
							part.status = row.status == "on" and "on" or "ready"
							part.reasons = { R("on", L["Goes with its page"], tab.name) }
							part.main = part.reasons[1]
						end
						row.parts[#row.parts + 1] = part
					end
				end
				if #row.parts == 0 then row.parts, row.partsLabel = nil, nil end
			end
			rows[#rows + 1] = row
		end
	end
	return { label = label, rows = rows }
end

-- Cards -----------------------------------------------------------------

local function CardName(id)
	local event = ns.CARD_BY_ID and ns.CARD_BY_ID[id]
	return L[event and event.name or tostring(id)]
end

local function CardNow()
	local current, waiting = ns.Cards.Queue()
	local held, showIn = ns.Cards.Held()
	local reasons = {}
	if current then
		reasons[1] = R("on", L["On screen: %s"]:format(CardName(current.id)), "Card Vision")
	end
	if not ns.Setting("cards") then
		reasons[#reasons + 1] = R("block", L["Card Vision is off"], "Card Vision")
	end
	local names = {}
	for _, card in ipairs(waiting) do names[#names + 1] = CardName(card.id) end
	if #names > 0 then
		reasons[#reasons + 1] = R("block", L["Waiting their turn: %s"]:format(table.concat(names, ", ")))
	end
	names = {}
	for id in pairs(held) do names[#names + 1] = CardName(id) end
	if #names > 0 then
		reasons[#reasons + 1] = R("block", showIn and L["Held through the fight: %s (in %d sec)"]:format(
			table.concat(names, ", "), math.ceil(showIn)) or L["Held through the fight: %s (till it's over)"]:format(
			table.concat(names, ", ")))
	end
	if not current then reasons[#reasons + 1] = R("off", L["No card on screen"], "Card Vision") end
	return { key = "card:now", title = L["Card now"], status = current and "on" or "idle",
		label = current and L["PLAYING"] or L["NONE"], reasons = reasons, settingsPage = "Card Vision",
		right = current and CardName(current.id) or nil }
end

local FIGHT_WORDS = { show = "In a fight: Show now", wait = "In a fight: Wait till after" }
local function CardRow(event, playing)
	local id = event.id
	local allowed, why, yield = ns.CardAllowed(id)
	local reasons, status, word = {}, "ready", nil
	if playing then
		status, word = "on", L["PLAYING"]
		reasons[1] = R("on", L["On screen now"], "Card Vision")
	elseif allowed then
		reasons[1] = R("on", L["Ticked, and its Show in row says yes here and now: it shows as its moment comes"],
			"Card Vision")
	else
		status = yield and "held" or "off"
		reasons[1] = R("block", why or L["Off"], "Card Vision")
	end
	if event.inFight then
		local fight = ns.db["cardFight_" .. id]
		reasons[#reasons + 1] = R("off", L[FIGHT_WORDS[fight] or "In a fight: Don't show"], "Card Vision")
	end
	local last = ns.WhyLastMoment and ns.WhyLastMoment("card:" .. id)
	if last then
		reasons[#reasons + 1] = R("off", L["Last: %s, %s"]:format(last.outcome, ns.WhyAgo(last.at)) ..
			(last.text and (": " .. last.text) or ""))
	end
	return { key = "card:" .. id, title = CardName(id), status = status, label = word, reasons = reasons,
		main = reasons[1], settingsPage = "Card Vision", right = last and ns.WhyAgo(last.at) or nil }
end

ns.WhyProvider("cards", "Cards", "The card on screen and the ones waiting. Below that, whether each card would show if its " ..
	"moment came now, and why not if it wouldn't.", function()
	local sections = { { label = "Right now", rows = { CardNow() }, keepOrder = true } }
	local current = ns.Cards.Queue()
	local byGroup = {}
	for _, event in ipairs(ns.CardEventsGrouped()) do
		local group = byGroup[event.group]
		if not group then
			group = { label = event.group, rows = {} }
			byGroup[event.group] = group
			sections[#sections + 1] = group
		end
		local ok, row = pcall(CardRow, event, current and current.id == event.id)
		if ok then group.rows[#group.rows + 1] = row end
	end
	return sections
end)

-- (After Cards, so the tabs go Cameras, Cards, Visions.)
ns.WhyProvider("visions", "Visions", "Each Vision and Atmosphere page with its tabs: whether it's on now, ready for its moment, or " ..
	"off, and which switch turned it off.", function()
	return { HubSection("Visions", "Visions"), HubSection("Atmosphere", "Atmosphere") }
end)

-- Quality of Life and the Wheels: at the end of the Interface tab, by their switches.
ns.WhyProvider("qol", "Quality of Life", nil, function()
	return { HubSection("Quality of life", "Quality of Life"), HubSection("Wheels", "Wheels") }
end, "interface")

-- Coverage ----------------------------------------------------------------
-- For the offline checks (Tools/offline/check.lua): what the Why window
-- would leave out or can't build, each as a line. Every tab built without an
-- error; every page of the hubs it lists by their switches with a line on
-- what it's for (WHEN); every camera with one (CAM_WHEN); and every hub on
-- some tab (WHY_HUBS: the Interface hub's are the frames' rows; Style's
-- looks, Help's, Community's and the dev copy's do nothing to explain).
local SWITCH_HUBS = { "Camera", "Visions", "Atmosphere", "Quality of life", "Wheels" }
local WHY_HUBS = { ["UI Manager"] = true, Addons = true, Style = true, Help = true, Community = true, Dev = true }
for _, hub in ipairs(SWITCH_HUBS) do WHY_HUBS[hub] = true end
function ns.WhyCoverage()
	local gaps = {}
	for _, provider in ipairs(ns.WhyProviders()) do
		local ok, sections = pcall(provider.fn)
		if not ok then
			gaps[#gaps + 1] = ("the %s tab errors: %s"):format(provider.id, tostring(sections))
		elseif type(sections) ~= "table" then
			gaps[#gaps + 1] = ("the %s tab gives no sections"):format(provider.id)
		end
	end
	for _, hub in ipairs(SWITCH_HUBS) do
		for _, icon in ipairs(ns.HubIcons(hub)) do
			if Listed(icon) and not WHEN[icon.name] then
				gaps[#gaps + 1] = ("%s > %s has no line on what it's for (WhyFeatures.lua's WHEN)"):format(hub, icon.name)
			end
		end
	end
	for _, cam in ipairs(ns.CAMERA_OFF_CAMS) do
		if not CAM_WHEN[cam[1]] then
			gaps[#gaps + 1] = ("the %s camera has no line on when it plays (WhyFeatures.lua's CAM_WHEN)"):format(cam[1])
		end
	end
	for _, hub in ipairs(ns.HubNames()) do
		if not WHY_HUBS[hub] then
			gaps[#gaps + 1] = ("the %s hub isn't on any tab (WhyFeatures.lua's WHY_HUBS)"):format(hub)
		end
	end
	return gaps
end

-- Addons ----------------------------------------------------------------
-- Every loaded addon Cinematic knows: each frame of its that's faded (its
-- row's status, as the Interface tab has it), its conflicts and their picks
-- (AddonSupport.lua's ns.CONFLICTS), what's done for it with no frames
-- (ns.ADDON_NOTES); then the loaded addons Cinematic does nothing with.

local GetNum = (C_AddOns and C_AddOns.GetNumAddOns) or GetNumAddOns
local GetInfo = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
local IsLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded

local function Bare(text)
	return (tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end
local function Loaded(addon)
	return ns.AddOnLoaded and ns.AddOnLoaded(addon) and true or false
end
local SUPPORT_OFF = "Its support is off (Addons > Custom Support): back on after a /reload"

-- A faded frame's row, as the Interface tab works it out (why.Explain).
local FRAME_STATUS = { shown = "on", partly = "on", game = "on", hidden = "off" }
local FRAME_WORD = { shown = "SHOWING", partly = "PARTLY SHOWN", game = "SET BY THE GAME", hidden = "HIDDEN" }
local function FrameRow(known, first)
	local key = "addon:" .. known.key
	local row = { key = "addonframe:" .. known.key, title = L[known.short or known.label or known.key],
		settingsPage = "Advanced Frames" }
	if not ns.AddonSupportOn(known.addon) then
		row.status, row.reasons = "off", { R("block", L[SUPPORT_OFF], "Addon Support") }
		return row
	end
	local info = first and first[key]
	local ok, status, reasons = false, nil, nil
	if info then
		local okExplain, _, explained, why = pcall(ns.why.Explain, info.entry)
		ok, status, reasons = okExplain, explained, why
	end
	if not (ok and type(reasons) == "table") then
		local on = ns.IsAddonFramesOn and ns.IsAddonFramesOn(known.key)
		row.status = on and "ready" or "off"
		row.reasons = { R(on and "on" or "block", on and L["Faded with its row: none of its frames are up yet"]
			or L["Its row is off on Addons > Loaded, so Cinematic leaves it be"], "Advanced Frames") }
		return row
	end
	if (status == "shown" or status == "partly") and not info.onScreen then
		row.status, row.label = "idle", L["NOT ON SCREEN"]
		table.insert(reasons, 1, R("on", L["Cinematic isn't hiding it: the addon isn't showing it right now"]))
	else
		row.status, row.label = FRAME_STATUS[status] or "idle", FRAME_WORD[status] and L[FRAME_WORD[status]] or nil
	end
	row.reasons = reasons
	return row
end

local function ConflictRow(conflict)
	local addon = conflict.addon
	local title = L["%s: %s"]:format(addon, L[conflict.label or conflict.key])
	local theirsOn = ns.ConflictTheirsOn(conflict)
	local pick, picked = ns.ConflictPick(conflict)
	local reasons, status, word = {}, "ready"
	if not theirsOn then
		word = L["THEIRS OFF"]
		reasons[1] = R("on", L["%s's own version is off, so Cinematic's plays"]:format(addon), "Addon Conflicts")
	elseif pick == "ours" then
		status, word = "on", L["OURS"]
		reasons[1] = R("on", L["Ours picked: Cinematic's plays, and %s's is hidden while it's on"]:format(addon),
			"Addon Conflicts")
	elseif pick == "both" then
		status, word = "on", L["BOTH"]
		reasons[1] = R("on", L["Both picked: Cinematic's and %s's both play"]:format(addon), "Addon Conflicts")
	else
		status, word = "held", L["THEIRS"]
		reasons[1] = R("block", picked and L["Theirs picked: %s's plays, and Cinematic's stands aside"]:format(addon)
			or L["Not picked yet, so %s's plays and Cinematic's stands aside"]:format(addon), "Addon Conflicts")
	end
	if conflict.about then reasons[#reasons + 1] = R("off", L[conflict.about]) end
	return { key = "conflict:" .. tostring(conflict.id), title = title, status = status, label = word,
		reasons = reasons, settingsPage = "Addon Conflicts" }
end

local function NoteRow(note)
	local on = ns.AddonSupportOn(note.addon)
	local reasons = { on and R("on", L[note.works or "Supported"], "Advanced Frames")
		or R("block", L[SUPPORT_OFF], "Addon Support") }
	if note.about then reasons[#reasons + 1] = R("off", L[note.about]) end
	return { key = "addonnote:" .. tostring(note.addon), title = L[note.label or note.addon],
		status = on and "on" or "off", label = on and L["WORKS"] or nil, reasons = reasons,
		settingsPage = "Advanced Frames" }
end

-- Loaded addons with nothing in Support/ (not Cinematic, not the game's own).
local function OthersRow()
	local parts = {}
	local count = GetNum and GetNum() or 0
	for i = 1, count do
		local ok, name, title = pcall(GetInfo, i)
		if ok and type(name) == "string" and not name:find("^Blizzard_") and not name:find("^Cinematic")
			and IsLoaded and IsLoaded(name) and not ns.IsSupportedAddon(name) then
			parts[#parts + 1] = { key = "otheraddon:" .. name,
				title = Bare((title ~= nil and title ~= "") and title or name),
				status = "idle", label = L["NOT FADED"], settingsPage = "Advanced Frames",
				reasons = { R("on", L["Cinematic does nothing with it"]),
					R("off", L["To fade one of its frames, add it on Addons > Loaded, or point at it with Pick a frame on screen"],
						"Advanced Frames") } }
		end
	end
	table.sort(parts, function(a, b) return a.title:lower() < b.title:lower() end)
	return { key = "otheraddons", title = L["Other addons loaded"], status = "idle", label = L["NOT FADED"],
		reasons = { R("on", L["Cinematic has no support for these, so it leaves their frames alone"]),
			R("off", L["Open this row for the list"]) },
		settingsPage = "Advanced Frames", parts = parts, partsLabel = L["%d addons"] }
end

ns.WhyProvider("addons", "Addons", "Every loaded addon Cinematic knows, with the frames it fades, the features you pick between " ..
	"(Conflicts) and what it does for the rest. Below that, the addons it leaves alone.", function()
	local faded, conflicts, notes = {}, {}, {}
	local order, first = ns.why.RowEntries()
	ns.why.LookAtRows(order, first)
	for _, known in ipairs(ns.ADDON_FRAMES) do
		if Loaded(known.addon) then
			local ok, row = pcall(FrameRow, known, first)
			if ok then faded[#faded + 1] = row end
		end
	end
	for _, conflict in ipairs(ns.CONFLICTS) do
		if Loaded(conflict.addon) then
			local ok, row = pcall(ConflictRow, conflict)
			if ok then conflicts[#conflicts + 1] = row end
		end
	end
	for _, note in ipairs(ns.ADDON_NOTES) do
		if Loaded(note.addon) then
			local ok, row = pcall(NoteRow, note)
			if ok then notes[#notes + 1] = row end
		end
	end
	local sections = {}
	if #faded > 0 then sections[#sections + 1] = { label = "Faded by Cinematic", rows = faded } end
	if #conflicts > 0 then sections[#sections + 1] = { label = "Conflicts", rows = conflicts } end
	if #notes > 0 then sections[#sections + 1] = { label = "Supported, nothing to fade", rows = notes } end
	local okOthers, others = pcall(OthersRow)
	if okOthers and others.parts and #others.parts > 0 then
		sections[#sections + 1] = { label = "Not supported", rows = { others } }
	end
	return sections
end)

-- Game settings ---------------------------------------------------------
-- Each set of the game's settings Cinematic holds for a while (Core.lua's
-- ns.cvarSets: named where it's made, or listed once first used), at the end
-- of the Interface tab: holding them now or not, what for, and to what.

local function CVarSetRow(set, i)
	local reasons = {}
	if set.active then
		reasons[1] = R("on", set.why and L[set.why] or L["In use now"], "Game settings")
	else
		reasons[1] = R("off", set.why and L[set.why] or L["Not in use now"], "Game settings")
	end
	local values = {}
	for cvar, value in pairs(type(set.values) == "table" and set.values or {}) do
		values[#values + 1] = ("%s = %s"):format(tostring(cvar), tostring(value))
	end
	table.sort(values)
	if #values > 0 then
		local shown = #values > 6 and { unpack(values, 1, 6) } or values
		reasons[#reasons + 1] = R("off", L["Sets: %s"]:format(table.concat(shown, ", ") ..
			(#values > 6 and (" " .. L["and %d more"]:format(#values - 6)) or "")))
	end
	if set.active and set.heldAt then
		reasons[#reasons + 1] = R("off", L["Since %s"]:format(ns.WhyAgo(set.heldAt)))
	elseif set.letGoAt then
		reasons[#reasons + 1] = R("off", L["Last let go %s"]:format(ns.WhyAgo(set.letGoAt)))
	end
	if set.keep then
		reasons[#reasons + 1] = R("off", L["Held by its page: Keep yours on the Game Settings page"], "Game settings")
	elseif set.playerWins then
		reasons[#reasons + 1] = R("off", L["Your own change wins: Keep yours on the Game Settings page"], "Game settings")
	end
	return { key = "cvarset:" .. i, title = L[set.label or "Game settings"], status = set.active and "on" or "idle",
		label = set.active and L["HOLDING"] or L["NOT NOW"], reasons = reasons, settingsPage = "Game settings",
		right = #values > 0 and L["%d settings"]:format(#values) or nil }
end

ns.WhyProvider("gamesettings", "Game settings", nil, function()
	-- (Those in use now a row each; the rest, often dozens, under one row.)
	local rows, idle = {}, {}
	for i, set in ipairs(ns.cvarSets or {}) do
		local ok, row = pcall(CVarSetRow, set, i)
		if ok then
			if row.status == "on" then rows[#rows + 1] = row else idle[#idle + 1] = row end
		end
	end
	local function ByTitle(a, b) return a.title < b.title end
	table.sort(rows, ByTitle)
	table.sort(idle, ByTitle)
	if #idle > 0 then
		rows[#rows + 1] = { key = "cvarsets:idle", title = L["Not in use now"], status = "idle", label = L["NOT NOW"],
			reasons = { R("on", L["Cinematic changes these only while something of its needs them"], "Game settings"),
				R("off", L["Open this row for the list"]) },
			settingsPage = "Game settings", parts = idle, partsLabel = L["%d sets"] }
	end
	if #rows == 0 then return {} end
	return { { label = "Game settings Cinematic changes", rows = rows } }
end, "interface")
