-- /cine debug whytest [steps]: one run checking the Why window (/cine why)
-- against the real game, step by step in the big test box (ns.PadTestBox):
-- what to do, a GET READY countdown, then RECORDING. Each step opens the
-- window at the tab it checks, logs what that tab's rows say whenever they
-- change ("whytest" in the saved log), takes screenshots, and ends with its
-- own verdict. Steps: 1 every tab in turn, 2 a Hearthstone (Teleport Vision
-- and the cameras), 3 a target (the Target row), 4 a Zone card (Cards and
-- Recent), 5 sitting still (the standing-still timer and the triggers), 6 the
-- world map (what pauses the timer), 7 the Recent tab. Numbers after it run
-- just those steps. Typed again: stops. Dev copy only (CinematicDev.toc).
local _, ns = ...

local READY = 4 -- seconds to read a step before it records
local run

local function Log(text) ns.Log("whytest", text) end
local function Bare(text)
	return (tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end
-- A row of a tab by its key, or nil.
local function Find(tab, key)
	local ok, found = pcall(ns.WhyGather, tab)
	if not ok then return nil, found end
	for _, item in ipairs(found) do
		if item.key == key then return item end
	end
end
local function Line(item)
	if not item then return "missing" end
	return ("[%s%s] %s: %s"):format(item.status, item.label and ("/" .. Bare(item.label)) or "", Bare(item.title),
		item.main and Bare(item.main.text) or "-")
end
-- Every top row of a tab, one log line each (parts left out).
local function Snapshot(tab)
	local ok, found = pcall(ns.WhyGather, tab)
	if not ok then
		Log(("tab %s: ERROR %s"):format(tab, tostring(found)))
		return nil
	end
	local count = 0
	for _, item in ipairs(found) do
		if not item.parent then
			count = count + 1
			Log(("  %s | %s"):format(tab, Line(item)))
		end
	end
	Log(("tab %s: %d rows"):format(tab, count))
	return count
end
-- A screenshot, named in the log by step and time (from a function of ours:
-- the game won't take Screenshot passed to a timer as it is).
local function Shot(what)
	C_Timer.After(0.3, function()
		Log(("screenshot %s at %s"):format(what, date("%H:%M:%S")))
		Screenshot()
	end)
end
-- The row's line, logged whenever it changes.
local function Watch(s, name, item)
	local line = Line(item)
	s.lines = s.lines or {}
	if s.lines[name] ~= line then
		s.lines[name] = line
		Log(("%.1fs %s: %s"):format(GetTime() - run.stepAt, name, line))
	end
end
local function MomentSince(key)
	local moment = ns.WhyLastMoment and ns.WhyLastMoment(key)
	return moment and moment.at >= run.stepAt - READY and moment or nil
end

local STEPS = {
	{ name = "tabs", say = "Just watch: the Why window opens on each of its tabs in turn.", length = 14,
		prep = function() ns.WhyWindowTab("interface") end,
		tick = function(s, t)
			local tabs = { "interface", "cameras", "cards", "visions", "addons", "recent" }
			local at = math.min(#tabs, math.floor(t / 2.2) + 1)
			if s.at ~= at then
				s.at = at
				ns.WhyWindowTab(tabs[at])
				s.counts = s.counts or {}
				s.counts[tabs[at]] = Snapshot(tabs[at]) or "ERROR"
				Shot("1 tab " .. tabs[at])
			end
		end,
		verdict = function(s)
			local out, bad = {}, false
			for _, tab in ipairs({ "interface", "cameras", "cards", "visions", "addons", "recent" }) do
				local count = s.counts and s.counts[tab]
				out[#out + 1] = ("%s %s"):format(tab, tostring(count or "not reached"))
				if count == "ERROR" or count == nil or (count == 0 and (tab == "interface" or tab == "cameras"
					or tab == "cards" or tab == "visions")) then bad = true end
			end
			return not bad, table.concat(out, ", ")
		end },
	{ name = "hearth", say = "Cast your Hearthstone. After about 3 seconds, move to cancel it.", length = 20,
		prep = function() ns.WhyWindowTab("visions", "page:Teleport Vision") end,
		tick = function(s)
			local casting = ns.Flag(UnitCastingInfo("player")) and true or false
			if casting and not s.cast then
				s.cast = true
				Log("cast seen: " .. tostring(UnitCastingInfo("player")))
				C_Timer.After(1.5, function() if run and run.s == s then Shot("2 hearth casting") end end)
			end
			if ns.TeleportVisionShown and ns.TeleportVisionShown() then s.portal = true end
			local row = Find("visions", "page:Teleport Vision")
			Watch(s, "Teleport Vision row", row)
			if row and row.status == "on" then s.on = true end
			Watch(s, "Camera now", Find("cameras", "cam:now"))
		end,
		verdict = function(s)
			local db = ns.db
			local context = ("page %s, portal shown %s, row on now %s, on Recent %s"):format(
				tostring(db.teleportVision), tostring(s.portal or false), tostring(s.on or false),
				tostring(MomentSince("page:Teleport Vision") ~= nil))
			if not s.cast then return nil, "no cast seen. " .. context end
			if s.on and MomentSince("page:Teleport Vision") then return true, context end
			if not s.portal then return false, "the portal never showed (page off, or its scene not playing). " .. context end
			return false, context
		end },
	{ name = "target", say = "Target anything near you, a creature or a player, and keep it targeted.", length = 15,
		prep = function() ns.WhyWindowTab("interface", "target") end,
		tick = function(s)
			local row = Find("interface", "target")
			Watch(s, "Target row", row)
			if ns.Flag(UnitExists("target")) then
				if not s.with then Shot("3 target") end
				s.with = row
			else
				s.without = row
			end
		end,
		verdict = function(s)
			local out = ("without a target %s; with one %s"):format(Line(s.without), Line(s.with))
			if not s.with then return nil, "nothing was targeted. " .. out end
			if s.with.status == "idle" then return false, "still not on screen with a target. " .. out end
			if s.without and s.without.main and Bare(s.without.main.text) ~= ns.L["No target"] then
				return false, "with no target it didn't say No target. " .. out
			end
			return true, out
		end },
	{ name = "card", say = "Just watch: a Zone card plays on its own.", length = 12,
		prep = function()
			ns.WhyWindowTab("cards", "card:now")
		end,
		tick = function(s, t)
			if not s.fired then
				s.fired = true
				local ok, shows = pcall(ns.Cards.Fire, "zone", ns.CardSample("zone"))
				Log(("fired the Zone card: %s %s"):format(tostring(ok), tostring(shows)))
				Shot("4 card")
			end
			Watch(s, "Card now", Find("cards", "card:now"))
			Watch(s, "Zone row", Find("cards", "card:zone"))
			if t > 3 and not s.shotRecent then
				s.shotRecent = true
				ns.WhyWindowTab("recent")
				Shot("4 card recent")
			end
		end,
		verdict = function()
			local moment = MomentSince("card:zone")
			if not moment then return false, "nothing on Recent for the Zone card" end
			return true, ("Recent: %s, %s"):format(moment.outcome, tostring(moment.text))
		end },
	{ name = "sit", say = "Type /sit and stay still. Don't move or turn until this step ends.", length = 24,
		prep = function() ns.WhyWindowTab("cameras", "cam:now") end,
		tick = function(s, t)
			local still = Find("cameras", "cam:still")
			Watch(s, "Timer row", still)
			Watch(s, "Camera now", Find("cameras", "cam:now"))
			if still and (still.status == "ready" or still.status == "on") then s.ran = true end
			local seen = ns.triggerPickSeen
			if seen and GetTime() - seen.at < 1 and seen.n > 0 then
				local keys = {}
				for i = 1, seen.n do keys[#keys + 1] = tostring(seen[i].key) end
				local list = table.concat(keys, ", ")
				if s.triggers ~= list then
					s.triggers = list
					Log(("%.1fs triggers on: %s (won: %s)"):format(t, list, tostring(seen.won)))
				end
			end
			if t > 12 and not s.shot then
				s.shot = true
				Shot("5 sit")
			end
		end,
		verdict = function(s)
			local out = ("timer ran %s, triggers seen: %s"):format(tostring(s.ran or false), tostring(s.triggers or "none"))
			if not s.ran then return false, out end
			if not s.triggers then return false, "the timer ran, but no trigger list was ever seen. " .. out end
			return true, out
		end },
	{ name = "map", say = "Open your world map (M) for a few seconds, then close it.", length = 16,
		prep = function() ns.WhyWindowTab("cameras", "cam:still") end,
		tick = function(s)
			local still = Find("cameras", "cam:still")
			Watch(s, "Timer row", still)
			local map = _G.WorldMapFrame
			if map and ns.Flag(map:IsShown()) then
				if not s.map then Shot("6 map") end
				s.map = true
				if ns.stillPausedBy == "window" and still and still.status == "held" then s.paused = true end
				if ns.stillPausedBy ~= s.why then
					s.why = ns.stillPausedBy
					Log("paused by: " .. tostring(ns.stillPausedBy))
				end
			end
		end,
		verdict = function(s)
			if ns.db.pauseCamsInWindows == false then return nil, "Pause in windows is off (Scenes page)" end
			if not s.map then return nil, "the map was never opened" end
			if s.paused then return true, "paused by the window, and the row said so" end
			return false, "the map was open but the row never said paused: paused by " .. tostring(s.why)
		end },
	{ name = "recent", say = "Just watch: the Recent tab.", length = 8,
		prep = function() ns.WhyWindowTab("recent") end,
		tick = function(s)
			if not s.done then
				s.done = true
				s.count = Snapshot("recent")
				Shot("7 recent")
			end
		end,
		verdict = function(s)
			if not s.count or s.count == 0 then return false, "Recent was empty" end
			return true, ("%d lines on Recent"):format(s.count)
		end },
}

local function Finish(stopped)
	run.ticker:Cancel()
	local passed, failed, skipped = 0, 0, 0
	for _, result in ipairs(run.results) do
		if result.ok == true then passed = passed + 1 elseif result.ok == false then failed = failed + 1
		else skipped = skipped + 1 end
	end
	local summary = ("%d passed, %d failed, %d skipped%s"):format(passed, failed, skipped, stopped and " (stopped)" or "")
	Log("done: " .. summary)
	ns.Print("Why test: " .. summary)
	ns.PadTestBox(stopped and "Test stopped." or "Test done.", summary .. ". /reload and say check log", 1, 0.82, 0)
	ns.TestPrompt(ns.L["Why test done: /reload and say check log"], 10)
	C_Timer.After(20, function() if not run then ns.PadTestBoxHide() end end)
	run = nil
end

local function Tick()
	local step = STEPS[run.order[run.at]]
	local now = GetTime()
	if not run.s then
		run.s, run.stepAt = {}, now + READY
		Log(("step %d %s: %s"):format(run.order[run.at], step.name, step.say))
		local ok, err = pcall(step.prep)
		if not ok then Log("prep error: " .. tostring(err)) end
	end
	local number = ("Step %d of %d"):format(run.at, #run.order)
	if now < run.stepAt then
		ns.PadTestBox(number .. ": " .. step.say, ("|cffffd100GET READY: starts in %d|r"):format(math.ceil(run.stepAt - now)))
		return
	end
	local t = now - run.stepAt
	local ok, err = pcall(step.tick, run.s, t)
	if not ok then Log("tick error: " .. tostring(err)) end
	if t < step.length then
		ns.PadTestBox(number .. ": " .. step.say, ("|cff40ff40RECORDING: %d sec left|r"):format(math.ceil(step.length - t)))
		return
	end
	local okVerdict, pass, text = pcall(step.verdict, run.s)
	if not okVerdict then pass, text = false, "verdict error: " .. tostring(pass) end
	local word = (pass == true and "PASS") or (pass == false and "FAIL") or "SKIPPED"
	Log(("verdict step %d %s: %s %s"):format(run.order[run.at], step.name, word, tostring(text)))
	run.results[#run.results + 1] = { ok = pass }
	run.at, run.s = run.at + 1, nil
	if run.at > #run.order then Finish() end
end

function ns.WhyTest(args)
	if run then return Finish(true) end
	local order = {}
	for number in tostring(args or ""):gmatch("%d+") do
		if STEPS[tonumber(number)] then order[#order + 1] = tonumber(number) end
	end
	if #order == 0 then
		for i = 1, #STEPS do order[i] = i end
	end
	run = { order = order, at = 1, results = {} }
	local db = ns.db
	Log(("start: steps %s | Cinematic %s, %s | CineMode %s | Why page %s | Teleport Vision %s, Card Vision %s, " ..
		"Enable Cameras %s, Pause in windows %s"):format(table.concat(order, " "), ns.Version and ns.Version() or "?",
		ns.isRetail and "retail" or ("game " .. tostring(select(4, GetBuildInfo()))), tostring(ns.lastCinematic and true),
		tostring(ns.WhyPageOn and ns.WhyPageOn()), tostring(db.teleportVision), tostring(db.cards),
		tostring(db.cameraModes), tostring(db.pauseCamsInWindows)))
	run.ticker = C_Timer.NewTicker(0.25, function()
		local ok, err = pcall(Tick)
		if not ok then
			Log("error: " .. tostring(err))
			if run then Finish(true) end
		end
	end)
	ns.Print(("Why test: %d steps, follow the box at the top of the screen (type it again to stop)"):format(#order))
end
