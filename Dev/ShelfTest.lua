-- /cine debug shelf: one run checking the welcome window's See all shelf
-- (Welcome.lua's BuildDemoRow, docs/design/welcome-shelf.md). It opens the
-- welcome window and does it all itself, logging ("shelftest") and giving its
-- own verdicts:
--   size:    the window's height closed and open (open = closed + the
--            shelf), and the biggest UI scale it fits the screen at;
--   groups:  each group clicked, the tiles it shows (All: every one);
--   search:  "roll" (Roll Vision's tile), "zzz" (none, the empty line);
--   tiles:   each tile clicked in turn (not the Shoulder Cam's: trying it is
--            agreeing to its experimental setting), up to 8 seconds or till
--            it ends, Stop clicked if still going; whether it played (Stop
--            on it, or one shown and done), Lua errors meanwhile, a
--            screenshot each 2 s in, and with it whether it's ON SCREEN
--            by what it draws (SHOWS, below); at the end a result line
--            per tile (on screen, not, can't play here and why), on the
--            level you're trying;
--   turn on: Subtle picked by its card (the user's OK: a level missing
--            things), the first tile offering Turn on clicked: its tag
--            after, the button gone; then your level's card again and
--            Subtle's saved changes put back as they were;
--   saved:   the shelf closed again, the window back to its height, the
--            open state saved and cleared.
-- Stand still (the camera tiles end when you move). CineMode off while it
-- runs (the user's rule: Start in CineMode off, Cinematic itself on, which
-- its cameras need), back after. Not in a fight (the fight line can't
-- be pretended: it's checked by its own words, which the log shows).
-- Typed again while running: stops. Dev copy only (CinematicDev.toc).
local _, ns = ...

local PLAY_FOR = 8   -- seconds a tile's watched at most
local SHOT_AT = 2
local SKIP = { shoulder = "trying it agrees to its experimental camera setting" }
-- (ShowMe.lua's once demos: shown and done, no Stop. Any other not running
-- right after its click didn't start: the quest camera, 2026-11-20.)
local ONCE = { cards = true, recap = true, cdflash = true, speech = true }
local run -- this run: verdicts, results by tile, what to put back
-- Whether it's on screen, by the feature's own reading, at the screenshot
-- (these showed nothing before a level's picked, 2026-11-20: their switches
-- were off; ShowMe.lua now turns them on while they play).
-- Whether each tile shows something, by what it draws (its frame on screen,
-- or the feature's own reading), at the screenshot. Every tile has one, the
-- user's ask 2026-11-20 ("did we test each here?"): before, only that it
-- started and stopped without an error, which said nothing of the screen.
-- Each gives on (true/false, nil: no reading) and a detail for the log.
local function Effective(frame)
	local alpha = frame and frame.GetEffectiveAlpha and frame:GetEffectiveAlpha()
	if type(alpha) ~= "number" or (issecretvalue and issecretvalue(alpha)) then return nil end
	return alpha
end
-- A frame by name, shown with some alpha on screen.
local function Seen(name)
	local frame = _G[name]
	if not frame then return false, name .. " not made" end
	local alpha = Effective(frame)
	local shown = ns.Flag(frame:IsVisible())
	return shown and (alpha or 0) > 0.05, ("%s %s, alpha %s"):format(name, shown and "shown" or "hidden",
		alpha and ("%.2f"):format(alpha) or "?")
end
-- One of our cameras holding the view (Core.lua's camera lock): who.
local function CameraMoving()
	local who = ns.CameraHolder and ns.CameraHolder()
	return who ~= nil and who ~= "you", ("view held by %s, zoom %.1f"):format(tostring(who),
		GetCameraZoom and GetCameraZoom() or -1)
end
-- A line of text on screen, a few levels under UIParent and our overlay holder.
local function TextOnScreen(words)
	local function Find(frame, depth)
		-- (a forbidden frame, a nameplate's: not ours to read, 2026-11-20 errored here)
		if frame.IsForbidden and frame:IsForbidden() then return false end
		if not ns.Flag(frame:IsVisible()) then return false end
		for _, region in ipairs({ frame:GetRegions() }) do
			if region.GetText and not (region.IsForbidden and region:IsForbidden()) and region:IsVisible() then
				local text = region:GetText()
				if type(text) == "string" and not (issecretvalue and issecretvalue(text)) and text:find(words, 1, true) then
					return true
				end
			end
		end
		if depth < 5 then
			for _, child in ipairs({ frame:GetChildren() }) do
				if Find(child, depth + 1) then return true end
			end
		end
		return false
	end
	local holder = _G.CinematicOverlayHolder
	return Find(UIParent, 0) or (holder and Find(holder, 0)) or false
end
local WATCH = { "PlayerFrame", "MainActionBar", "MainMenuBar", "ChatFrame1", "Minimap" }
local SHOWS = {
	fadeUI = function()
		local low, parts = 1, {}
		for _, name in ipairs(WATCH) do
			local frame = _G[name]
			local alpha = frame and ns.Flag(frame:IsShown()) and Effective(frame)
			if alpha then
				low = math.min(low, alpha)
				parts[#parts + 1] = ("%s %.2f"):format(name, alpha)
			end
		end
		return low < 0.2, "UIParent " .. ("%.2f"):format(UIParent:GetAlpha()) .. "; " .. table.concat(parts, ", ")
	end,
	bars = function() return Seen("CinematicLetterbox") end,
	-- (What the tint drew, Tint.lua's ns.tintDrawn: its frame was shown with
	-- nothing visible, the user saw no tint, 2026-11-20. On screen: a real
	-- strength. The color: how far from white (none) it is.)
	tint = function()
		local d = ns.tintDrawn
		local _, frame = Seen("CinematicTint")
		if not d then return false, frame .. "; nothing drawn yet" end
		local away = d.none and 0 or math.max(1 - (d.r or 1), 1 - (d.g or 1), 1 - (d.b or 1))
		return not d.none and (d.strength or 0) > 0.05 and away > 0.05, ("%s; preset %s, mode %s, strength %.2f, level %.2f, " ..
			"color %.2f %.2f %.2f (%.2f from none), drawn %s, Tint strength setting %.2f"):format(frame, tostring(d.preset),
			tostring(d.mode), d.strength or 0, d.level or 0, d.r or 1, d.g or 1, d.b or 1, away, tostring(not d.none),
			ns.db.tintStrength or 1)
	end,
	-- (Weather draws only with rain, snow or dust in the zone: its level logged, no verdict.)
	weather = function()
		local d = ns.tintDrawn
		return nil, ("weather level %s, the zone's weather call %s"):format(tostring(d and d.weather),
			C_Weather and "present" or "absent")
	end,
	camera = CameraMoving,
	vitals = function() return ns.VitalsVisionActive and ns.VitalsVisionActive() end,
	emote = function() return ns.EmoteCardShown and ns.EmoteCardShown(), "emote card" end,
	timeTitle = function()
		local card = ns.Cards and ns.Cards.Current and ns.Cards.Current()
		local on, detail = Seen("CinematicCard")
		return on and card ~= nil and card.id == "time", detail .. ", card " .. tostring(card and card.id)
	end,
	cards = function()
		local card = ns.Cards and ns.Cards.Current and ns.Cards.Current()
		local on, detail = Seen("CinematicCard")
		return on and card ~= nil, detail .. ", card " .. tostring(card and card.id)
	end,
	-- (A sound: what the call played, caught as it ran; the ear says the rest.)
	-- (CineMode's music, ShowMe.lua's demo: the game's music on, at a volume
	-- you can hear by the screenshot; your own already on counts.)
	audio = function()
		if not ns.MusicDemoState then return false, "no music demo" end
		local playing, yours, enabled, volume = ns.MusicDemoState()
		return playing and enabled == "1" and (tonumber(volume) or 0) > 0.05,
			("demo %s, your own music %s, music on %s, volume %s"):format(tostring(playing), tostring(yours),
				tostring(enabled), tostring(volume))
	end,
	damage = function() return Seen("CinematicDamageVision") end,
	recap = function()
		local on, detail = Seen("CinematicDamageRecap")
		return on or (ns.DamageRecapShowing and ns.DamageRecapShowing()) or false, detail
	end,
	deathVision = function()
		local d = ns.GetCorpseDebug and ns.GetCorpseDebug()
		return d and d.shown and (d.wash or 0) > 0, d and ("wash %.2f, creep %.2f"):format(d.wash or 0, d.creep or 0)
	end,
	-- (and clear of the welcome window, on its left: it opened behind it, 2026-11-20)
	roll = function()
		local roll, window = _G.CinematicRolls, _G.CinematicWelcome
		local on = ns.RollVisionActive and ns.RollVisionActive()
		if not (roll and window and roll:GetRight() and window:GetLeft()) then return on, "no position" end
		local right = roll:GetRight() * roll:GetEffectiveScale()
		local left = window:GetLeft() * window:GetEffectiveScale()
		return on and right <= left + 1, ("roll window's right edge %.0f px, welcome window's left %.0f px%s"):format(
			right, left, right <= left + 1 and ", clear of it" or ", OVER IT")
	end,
	tele = function() return ns.TeleportVisionShown and ns.TeleportVisionShown(), "portal" end,
	cdflash = function()
		return ns.CooldownFlashTesting and ns.CooldownFlashTesting(GetTime()), "flash test running"
	end,
	speech = function()
		return TextOnScreen(ns.L["Speech from behind you shows here."]), "its line searched for on screen"
	end,
}
for _, key in ipairs({ "afk", "questCam", "flight", "cozy", "vista", "fish", "deathCam", "walk", "run" }) do
	SHOWS[key] = CameraMoving
end
-- What a camera's Test goes by as it starts (QuestCam.lua's Wanted, CameraTests.lua).
local function CameraWhy()
	return ("enabled %s, Quest scene camera %s, quest cam off here %s, quest calm wait over %s, on taxi %s, " ..
		"pretend travel %s, moving %s, manual cam %s"):format(tostring(ns.db.enabled),
		tostring(ns.TriggerHasCamera and ns.TriggerHasCamera("Quest")),
		tostring(ns.IsCameraOffHere and ns.IsCameraOffHere("quest")),
		tostring(ns.CombatWaitOver and ns.CombatWaitOver("quest", GetTime())), tostring(ns.OnTaxi and ns.OnTaxi()),
		tostring(ns.testTravel), tostring(ns.playerMoving), tostring(ns.manualCam))
end

local function Log(text) ns.Log("shelftest", text) end
local function Errors() return ns.DevErrorCount and (ns.DevErrorCount("error")) or 0 end
local function Verdict(ok, what)
	local line = (ok and "PASS " or "FAIL ") .. what
	run.verdicts[#run.verdicts + 1] = line
	Log("verdict: " .. line)
end

-- The demo row (the frame with SetShelfOpen) in the welcome window.
local function FindRow(frame, depth)
	if frame.SetShelfOpen then return frame end
	if depth > 6 then return nil end
	for _, child in ipairs({ frame:GetChildren() }) do
		local found = FindRow(child, depth + 1)
		if found then return found end
	end
end
local function Each(frame, test, out, depth)
	out = out or {}
	if test(frame) then out[#out + 1] = frame end
	if (depth or 0) < 8 then
		for _, child in ipairs({ frame:GetChildren() }) do Each(child, test, out, (depth or 0) + 1) end
	end
	return out
end

-- One step after another: each fn(next) calls next when done.
local function Steps(list)
	local i = 0
	local function Next()
		if not run then return end
		i = i + 1
		while list[i] == false do i = i + 1 end -- (a part not asked for)
		local step = list[i]
		if not step then return end
		C_Timer.After(0.3, function()
			if not run then return end
			local ok, err = pcall(step, Next)
			if not ok then
				Log("step error: " .. tostring(err))
				Verdict(false, "step " .. i .. " ran without an error: " .. tostring(err))
				Next()
			end
		end)
	end
	Next()
end

local function Finish(stopped)
	if not run then return end
	if ns.ShowMeRunning and run.row then
		for _, b in ipairs(run.row.ShelfTiles()) do
			if ns.ShowMeRunning(b.demo.key) then ns.StopShowMe() end
		end
	end
	-- (stopped on Subtle: yours again, Subtle's saved changes as they were)
	if run.switchBack then pcall(run.switchBack) end
	-- (after the settings above: they were saved with it off)
	ns.db.fadeUI = run.fadeUI
	if ns.RestartTimers then ns.RestartTimers() end
	local fails = 0
	for _, line in ipairs(run.verdicts) do
		if line:find("^FAIL") then fails = fails + 1 end
	end
	local summary = stopped and "stopped" or (fails == 0 and ("all PASS (%d)"):format(#run.verdicts)
		or ("%d FAIL of %d"):format(fails, #run.verdicts))
	Log("summary: " .. summary)
	ns.Print("Shelf test: " .. summary)
	ns.PadTestBox(stopped and "Test stopped." or "Test done.", "/reload, then say: check log", 1, 0.82, 0)
	C_Timer.After(20, function() if not run then ns.PadTestBoxHide() end end)
	run = nil
end

local function Visible(row)
	local names = {}
	for _, b in ipairs(row.ShelfTiles()) do
		if b:IsShown() then names[#names + 1] = b.demo.key end
	end
	return names
end

local function TileStep(b)
	return function(Next)
		local key = b.demo.key
		if SKIP[key] then
			Log(("tile %s: skipped, %s"):format(key, SKIP[key]))
			run.results[key] = "SKIPPED: " .. SKIP[key]
			return Next()
		end
		local why = ns.ShowMeBlocked(key, true)
		if why then
			Log(("tile %s: blocked: %s"):format(key, tostring(why)))
			run.blocked[#run.blocked + 1] = key .. " (" .. tostring(why) .. ")"
			run.results[key] = "CAN'T PLAY HERE: " .. tostring(why)
			return Next()
		end
		ns.TestPrompt(("Shelf test: %s. Stand still and watch."):format(ns.L[b.demo.label]), 4)
		local errors = Errors()
		local before = CameraWhy()
		b:Click()
		local running = ns.ShowMeRunning(key)
		Log(("tile %s: clicked, running %s, name now \"%s\", tag \"%s\""):format(key, tostring(running),
			tostring(b.name:GetText()), tostring(b.tag:GetText())))
		if not running and not ONCE[key] then
			Log(("tile %s: DIDN'T START; before the click: %s"):format(key, before))
			Verdict(false, key .. " started")
			return C_Timer.After(1, Next)
		end
		local began = GetTime()
		local shot = false
		local ticker
		ticker = C_Timer.NewTicker(0.25, function()
			if not run then ticker:Cancel() return end
			local t = GetTime() - began
			if not shot and t >= SHOT_AT then
				shot = true
				pcall(Screenshot)
				Log(("tile %s: screenshot at %s"):format(key, date("%H:%M:%S")))
				if SHOWS[key] then
					local ok, on, detail = pcall(SHOWS[key])
					if not ok then on, detail = false, "reading error: " .. tostring(on) end
					Log(("tile %s: on screen %s (%s), switches held %s"):format(key, tostring(on), tostring(detail),
						tostring(ns.db.showMeRestore ~= nil)))
					if on == nil then
						run.results[key] = "NO READING: " .. tostring(detail)
					else
						run.results[key] = (on and "ON SCREEN" or "NOT ON SCREEN") .. ": " .. tostring(detail)
						Verdict(on and true or false, key .. " shows on screen")
					end
				else
					run.results[key] = "NO READING"
				end
			end
			local still = ns.ShowMeRunning(key)
			if (still and t < PLAY_FOR) or t < SHOT_AT + 0.5 then return end
			ticker:Cancel()
			if still then
				b:Click()
				Log(("tile %s: Stop clicked at %.1f s, running after %s"):format(key, t, tostring(ns.ShowMeRunning(key))))
			else
				Log(("tile %s: ended by itself by %.1f s"):format(key, t))
			end
			local new = Errors() - errors
			-- (and its switches back off: ShowMe.lua's db.showMeRestore cleared)
			local ok = new == 0 and not ns.ShowMeRunning(key) and ns.db.showMeRestore == nil
			run.played[#run.played + 1] = key .. (running and "" or " (shown and done)")
			Verdict(ok, ("%s played and stopped clean (%d Lua errors, switches put back %s)"):format(key, new,
				tostring(ns.db.showMeRestore == nil)))
			C_Timer.After(1, Next)
		end)
	end
end

-- list: what to test, words apart ("questCam duel search"): tiles by their
-- keys, and the parts groups, search, turnon. None: everything. The size
-- and the closing again always run (a second, and they open the shelf).
local PARTS = { groups = true, search = true, turnon = true }
function ns.ShelfTest(list)
	-- (Never the Ctrl+C copy window over the game: the user's rule; its lines
	-- are in chat and the log. Set first: the start's lines opened it.)
	ns.debugNoCopyWindow = true
	if run then return Finish(true) end
	if InCombatLockdown() then
		ns.Print("Shelf test: not in a fight.")
		return
	end
	local only
	-- (the chat command comes lowercased: keys matched without case)
	for word in (list or ""):lower():gmatch("%S+") do
		only = only or {}
		only[word] = true
	end
	local function Want(key) return not only or only[key:lower()] == true end
	run = { verdicts = {}, played = {}, blocked = {}, results = {}, fadeUI = ns.db.fadeUI,
		savedWas = ns.db.welcomeShelf and ns.db.welcomeShelf.open }
	ns.ShowWelcome()
	local window = _G.CinematicWelcome
	local row = window and FindRow(window, 0)
	run.row = row
	Log(("start: client %s, UI scale %s, screen %s x %s, profile chosen %s, active %s"):format(tostring(ns.CLIENT),
		tostring(UIParent:GetEffectiveScale()), tostring(math.floor(UIParent:GetWidth())),
		tostring(math.floor(UIParent:GetHeight())), tostring(ns.ProfileChosen()), tostring(ns.ActiveProfile())))
	if not row then
		Verdict(false, "the welcome window has the See it first row with a shelf")
		return Finish(false)
	end
	-- (Every word one it knows, else the list of them, and nothing run.)
	if only then
		local known, keys = {}, {}
		for _, b in ipairs(row.ShelfTiles()) do
			known[b.demo.key:lower()] = true
			keys[#keys + 1] = b.demo.key:lower()
		end
		for word in pairs(only) do
			if not (known[word] or PARTS[word]) then
				ns.Print(("Shelf test: no \"%s\". Tiles: %s. Parts: groups, search, turnon."):format(word,
					table.concat(keys, ", ")))
				run = nil
				return
			end
		end
		local asked = {}
		for word in pairs(only) do asked[#asked + 1] = word end
		Log("only: " .. table.concat(asked, " "))
	end
	-- CineMode off without switching Cinematic off (its cameras won't start
	-- then: "Cinematic is off" in chat for every camera tile, 2026-11-20):
	-- Start in CineMode off, so it doesn't come in by itself. Put back.
	ns.db.fadeUI = false
	if ns.RestartTimers then ns.RestartTimers() end
	ns.Print(("Shelf test: %s, stand still, hands off (type it again to stop)"):format(
		only and "just what you named" or "about 4 minutes"))
	local closedH
	local steps = {}
	steps[#steps + 1] = function(Next)
		row.SetShelfOpen(false)
		closedH = window:GetHeight()
		row.SetShelfOpen(true)
		local openH = window:GetHeight()
		local screenPx = UIParent:GetHeight() * UIParent:GetEffectiveScale()
		local fitScale = screenPx / openH
		Log(("size: closed %.0f, open %.0f, saved open %s; open fits the screen up to UI scale %.2f (yours %.2f)")
			:format(closedH, openH, tostring(ns.db.welcomeShelf.open), fitScale, UIParent:GetEffectiveScale()))
		Verdict(openH > closedH + 100, ("the window grew with the shelf (%.0f to %.0f)"):format(closedH, openH))
		Verdict(window:GetTop() <= UIParent:GetTop() + 1 and window:GetBottom() >= -1,
			"the window open is on the screen")
		Verdict(fitScale >= 1, ("the window open fits at UI scale 1 (fits up to %.2f)"):format(fitScale))
		Verdict(ns.db.welcomeShelf.open == true, "open saved")
		Next()
	end
	steps[#steps + 1] = Want("groups") and function(Next)
		local groupButtons = Each(window, function(f) return f.group ~= nil and f.GetObjectType and f:IsShown() end)
		local all = #row.ShelfTiles()
		for _, g in ipairs(groupButtons) do
			g:Click()
			local names = Visible(row)
			Log(("group %s: %d tiles: %s"):format(g.group.key, #names, table.concat(names, ", ")))
			if g.group.key == "all" then
				Verdict(#names == all, ("All shows every tile (%d of %d)"):format(#names, all))
			else
				local ok = #names > 0
				for _, b in ipairs(row.ShelfTiles()) do
					if b:IsShown() and b.demo.group ~= g.group.key then ok = false end
				end
				Verdict(ok, ("%s shows only its own tiles (%d)"):format(g.group.key, #names))
			end
		end
		Log("saved group after the clicks: " .. tostring(ns.db.welcomeShelf.group))
		Verdict(groupButtons[#groupButtons] and ns.db.welcomeShelf.group == groupButtons[#groupButtons].group.key,
			"the last group saved")
		if groupButtons[1] then groupButtons[1]:Click() end
		Next()
	end
	steps[#steps + 1] = Want("search") and function(Next)
		local search = Each(window, function(f)
			return f.GetObjectType and f:GetObjectType() == "EditBox" and f:IsVisible()
		end)[1]
		if not search then
			Verdict(false, "the shelf has a search box")
			return Next()
		end
		-- (Each read a moment after: the box's text change may land a frame
		-- later. 2026-11-20 read at once, every tile was still shown.)
		local function After(fn) C_Timer.After(0.3, function() if run then fn() end end) end
		search:SetText("roll")
		After(function()
			local names = Visible(row)
			Log(("search roll (box says \"%s\"): %s"):format(tostring(search:GetText()), table.concat(names, ", ")))
			local found = false
			for _, name in ipairs(names) do found = found or name == "roll" end
			Verdict((found or not ns.ShowMeAvailable("roll")) and #names < #row.ShelfTiles(),
				"search \"roll\" finds Roll Vision, not every tile")
			search:SetText("zzz")
			After(function()
				names = Visible(row)
				Log("search zzz: " .. #names .. " tiles")
				Verdict(#names == 0, "search \"zzz\" finds nothing")
				search:SetText("")
				search:ClearFocus()
				After(function()
					Verdict(#Visible(row) == #row.ShelfTiles(), "the search cleared shows them all again")
					Next()
				end)
			end)
		end)
	end
	for _, b in ipairs(row.ShelfTiles()) do
		if Want(b.demo.key) then steps[#steps + 1] = TileStep(b) end
	end
	steps[#steps + 1] = Want("turnon") and function(Next)
		-- Turn on needs a level missing something: Subtle (the user's OK,
		-- 2026-11-20), picked by its card as a player would, then yours
		-- again by its card. Subtle's saved changes put back as they were.
		local cards, level = ns.WelcomeCards and ns.WelcomeCards() or {}, {}
		for i, each in ipairs(ns.WELCOME_LEVELS) do level[each.profile or ns.DEFAULT_PROFILE] = cards[i] end
		local mine = ns.ActiveProfile()
		local subtle = level.Subtle
		if not subtle or mine == "Subtle" then
			Log(("turn on: not tried (Subtle's card %s, active %s)"):format(tostring(subtle ~= nil), tostring(mine)))
			return Next()
		end
		local saved = ns.db.profiles and ns.db.profiles.Subtle
		local function Copy(t)
			if type(t) ~= "table" then return t end
			local out = {}
			for k, v in pairs(t) do out[k] = Copy(v) end
			return out
		end
		run.subtleSaved = saved and Copy(saved) or false
		run.switchBack = function()
			run.switchBack = nil
			if level[mine] then level[mine]:Click() else ns.SetProfile(mine) end
			-- (switching saved Subtle's live settings, Turn on's among them: as they were)
			ns.db.profiles.Subtle = run.subtleSaved or nil
			ns.db.fadeUI = false -- (CineMode still off for the rest of the test)
			Log(("turn on: back to %s (active %s), Subtle's saved changes put back"):format(mine,
				tostring(ns.ActiveProfile())))
		end
		subtle:Click()
		ns.db.fadeUI = false
		Log("turn on: Subtle picked, active " .. tostring(ns.ActiveProfile()))
		C_Timer.After(1.5, function()
			if not run then return end
			local offered, offers = nil, {}
			for _, b in ipairs(row.ShelfTiles()) do
				if b.turnOn and b.turnOn:IsShown() then
					offered = offered or b
					offers[#offers + 1] = b.demo.key
				end
			end
			Log("turn on: offered on Subtle: " .. (#offers > 0 and table.concat(offers, ", ") or "none"))
			Verdict(offered ~= nil, "Subtle offers Turn on for what it hasn't")
			if offered then
				local key = offered.demo.key
				Log(("turn on: %s, tag before \"%s\""):format(key, tostring(offered.tag:GetText())))
				offered.turnOn:Click()
				local live = {}
				for _, each in ipairs({ "cameraModes", "damageVision", "emoteVision", "rollWindow", "deathScreen",
					"duelPlates", "cards", "lowHealth", "teleportVision", "musicInCinematic" }) do
					live[#live + 1] = each .. " " .. tostring(ns.db[each])
				end
				Log(("turn on: %s, tag after \"%s\", button shown %s; live: %s"):format(key,
					tostring(offered.tag:GetText()), tostring(offered.turnOn:IsShown()), table.concat(live, ", ")))
				Verdict(offered.tag:GetText() == ns.L["On: you turned it on"], "Turn on: the tag says you turned it on")
				Verdict(not offered.turnOn:IsShown(), "Turn on: its button goes")
			end
			run.switchBack()
			C_Timer.After(1.5, function()
				if not run then return end
				Verdict(ns.ActiveProfile() == mine, "back on your profile, " .. tostring(mine))
				Next()
			end)
		end)
	end
	steps[#steps + 1] = function(Next)
		row.SetShelfOpen(false)
		Verdict(math.abs(window:GetHeight() - closedH) < 1, ("closed: the window back to %.0f"):format(closedH))
		Verdict(ns.db.welcomeShelf.open == nil, "closed saved")
		if run.savedWas then row.SetShelfOpen(true) end
		Log("played: " .. table.concat(run.played, ", "))
		Log("blocked: " .. (#run.blocked > 0 and table.concat(run.blocked, "; ") or "none"))
		-- (Every tile's result, one line each, the level they were tried on.)
		Log(("results on %s:"):format(tostring(ns.ActiveProfile())))
		for _, b in ipairs(row.ShelfTiles()) do
			local key = b.demo.key
			if run.results[key] then
				Log(("  result %s [tag \"%s\"]: %s"):format(key, tostring(b.tag:GetText()), run.results[key]))
			end
		end
		Next()
		Finish(false)
	end
	Steps(steps)
end
