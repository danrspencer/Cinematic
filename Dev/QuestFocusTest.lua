-- /cine debug questfocus: one run recording the Quest tracker page's "Show
-- just that quest" (Frames.lua's quest reveal and ns.QuestFocusTick) while
-- you quest for 4 minutes: every quest event, each quest the log scan saw
-- move on (tracked or not), each reveal (for which quest, the tracker's alpha
-- then, whether focus took), why focus let go, what kept the tracker up each
-- pass (on change), the tracker's shape (its sections and the quest IDs in
-- them) at the start and after each reveal, your settings and the other
-- addons' trackers. A screenshot 1.5 s after each reveal. Into its own saved
-- list, CinematicDB.questFocusLog. Typed again while running: stops.
-- Dev copy only (CinematicDev.toc).
local _, ns = ...

local LENGTH = 240 -- seconds
local MAX_LINES, MAX_SHOTS = 4000, 15

local run

function ns.questFocusRecKeys(set)
	local keys = {}
	for key in pairs(set or {}) do keys[#keys + 1] = tostring(key) end
	table.sort(keys)
	return #keys > 0 and table.concat(keys, ",") or "none"
end

local function Add(text)
	if not run then return end
	local log = run.log
	if #log >= MAX_LINES then return end
	log[#log + 1] = ("%7.2f %s"):format(GetTime() - run.start, text)
end

local function Shown(frame)
	if type(frame) ~= "table" or not frame.IsShown then return "none" end
	local okShown, shown = pcall(frame.IsShown, frame)
	local okAlpha, alpha = pcall(frame.GetEffectiveAlpha, frame)
	return ("shown %s, alpha %s"):format(okShown and tostring(shown) or "?",
		okAlpha and type(alpha) == "number" and ("%.2f"):format(alpha) or "?")
end

local function Watched(id)
	local log = C_QuestLog
	if type(id) ~= "number" or not (log and log.GetQuestWatchType) then return "?" end
	local ok, watch = pcall(log.GetQuestWatchType, id)
	return ok and tostring(watch) or "error"
end

-- The game tracker's sections and the quest IDs in each one's usedBlocks.
local function Shape(why)
	local tracker = _G.ObjectiveTrackerFrame
	Add(("shape (%s): ObjectiveTrackerFrame %s, modules %s, Header %s"):format(why, Shown(tracker),
		tracker and type(tracker.modules) == "table" and #tracker.modules or "no",
		tracker and Shown(tracker.Header) or "none"))
	if type(tracker) ~= "table" then return end
	local sections = type(tracker.modules) == "table" and tracker.modules or { tracker:GetChildren() }
	for i, section in ipairs(sections) do
		local okName, name = pcall(section.GetName, section)
		local line = ("  section %d %s: %s"):format(i, okName and tostring(name) or "?", Shown(section))
		if type(section.usedBlocks) == "table" then
			local ids = {}
			for template, blocks in pairs(section.usedBlocks) do
				if type(blocks) == "table" then
					for id in pairs(blocks) do
						ids[#ids + 1] = ("%s(%s, watch %s)"):format(tostring(id), type(id), Watched(id))
					end
				else
					ids[#ids + 1] = "template " .. tostring(template) .. " not a table"
				end
			end
			line = line .. ", blocks: " .. (#ids > 0 and table.concat(ids, " ") or "none")
		else
			line = line .. ", no usedBlocks"
		end
		Add(line)
	end
	local log = C_QuestLog
	if log and log.GetNumQuestWatches then
		local ok, count = pcall(log.GetNumQuestWatches)
		Add("  quest watches: " .. (ok and tostring(count) or "error"))
	end
end

local function Shot()
	Screenshot()
end

local function Finish(stopped)
	if not run then return end
	Shape("end")
	Add(stopped and "stopped" or "done")
	ns.questFocusRec = nil
	if run.timer then run.timer:Cancel() end
	run = nil
	ns.TestPrompt("Quest focus test done: /reload and say check log", 15)
end

local function Record(kind, text)
	if not run then return end
	-- (Each pass's state: only when it changes.)
	if kind == "tick" or kind == "why" or kind == "standin" then
		if run.last[kind] == text then return end
		run.last[kind] = text
	end
	Add(kind .. ": " .. text)
	if kind == "reveal" then
		C_Timer.After(0.6, function() if run then Shape("0.6 s after reveal") end end)
		if run.shots < MAX_SHOTS then
			run.shots = run.shots + 1
			local number = run.shots
			C_Timer.After(1.5, function()
				if run then
					Add(("screenshot %d (1.5 s after that reveal)"):format(number))
					Shot()
				end
			end)
		end
	end
end

-- "questfocus height": can the game's tracker be given room to draw every
-- tracked quest for a reveal? Out of combat: its height fields and methods,
-- then A (its Edit Mode height raised, its update called) and B (the frame
-- made taller, its update called), each counted (quests drawn), shot and
-- put back; whether its fields are still secure; then 3 minutes of play
-- (fights too) watching for blocked actions the tries may have left.
local HEIGHT_PLAY = 180
local BIG = 3000

local function Blocks()
	local section = _G.QuestObjectiveTracker
	local count = 0
	if type(section) == "table" and type(section.usedBlocks) == "table" then
		for _, blocks in pairs(section.usedBlocks) do
			if type(blocks) == "table" then
				for _ in pairs(blocks) do count = count + 1 end
			end
		end
	end
	return count
end

local function Fields(name, object)
	if type(object) ~= "table" then
		Add(name .. ": none")
		return
	end
	local out = {}
	for key, value in pairs(object) do
		if type(key) == "string" and (key:find("Height") or key:find("Layout") or key:find("Update")
			or key:find("Max") or key:find("Avail") or key:find("Size") or key:find("Dirty")) then
			out[#out + 1] = key .. "=" .. (type(value) == "function" and "fn" or tostring(value))
		end
	end
	table.sort(out)
	Add(name .. ": " .. (#out > 0 and table.concat(out, ", ") or "nothing matching"))
end

local function Measure(why)
	local tracker = _G.ObjectiveTrackerFrame
	local okH, height = pcall(tracker.GetHeight, tracker)
	local okT, top = pcall(tracker.GetTop, tracker)
	local okB, bottom = pcall(tracker.GetBottom, tracker)
	local watches = C_QuestLog and C_QuestLog.GetNumQuestWatches and C_QuestLog.GetNumQuestWatches()
	Add(("%s: height %s, top %s, bottom %s, editModeHeight %s, quests drawn %d of %s watched"):format(why,
		okH and tostring(height) or "?", okT and tostring(top) or "?", okB and tostring(bottom) or "?",
		tostring(tracker.editModeHeight), Blocks(), tostring(watches)))
end

local function Update(why)
	local tracker = _G.ObjectiveTrackerFrame
	local tries = {
		{ "ObjectiveTrackerFrame:UpdateHeight", tracker.UpdateHeight, tracker },
		{ "ObjectiveTrackerFrame:Update", tracker.Update, tracker },
		{ "ObjectiveTrackerManager:UpdateAll", _G.ObjectiveTrackerManager and _G.ObjectiveTrackerManager.UpdateAll,
			_G.ObjectiveTrackerManager },
		{ "ObjectiveTracker_Update", _G.ObjectiveTracker_Update },
	}
	local done = {}
	for _, try in ipairs(tries) do
		if type(try[2]) == "function" then
			local ok, err = pcall(try[2], try[3])
			done[#done + 1] = try[1] .. (ok and " ok" or (" error " .. tostring(err)))
		end
	end
	Add(why .. " update: " .. (#done > 0 and table.concat(done, "; ") or "no update function found"))
end

local function Secure(why)
	local tracker = _G.ObjectiveTrackerFrame
	local out = {}
	for _, key in ipairs({ "editModeHeight", "UpdateHeight", "Update" }) do
		local ok, secure, taint = pcall(issecurevariable, tracker, key)
		out[#out + 1] = ("%s %s%s"):format(key, ok and (secure and "secure" or "TAINTED") or "?",
			ok and taint and (" by " .. tostring(taint)) or "")
	end
	Add(why .. " secure: " .. table.concat(out, ", "))
end

local function HeightTest()
	local tracker = _G.ObjectiveTrackerFrame
	if type(tracker) ~= "table" then
		ns.Print("No game quest tracker.")
		return
	end
	if InCombatLockdown() then
		ns.Print("Out of combat first.")
		return
	end
	local db = ns.db
	db.questFocusLog = {}
	run = { log = db.questFocusLog, start = GetTime(), last = {}, shots = 0 }
	Add("height test start: client " .. (ns.isRetail and "retail" or "Forever/Classic"))
	run.events = CreateFrame("Frame")
	for _, event in ipairs({ "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do
		run.events:RegisterEvent(event)
	end
	run.events:SetScript("OnEvent", function(_, event, addon, action)
		Add(("%s: %s %s (in combat %s)"):format(event, tostring(addon), tostring(action), tostring(InCombatLockdown())))
	end)
	Fields("ObjectiveTrackerFrame", tracker)
	Fields("ObjectiveTrackerManager", _G.ObjectiveTrackerManager)
	Fields("QuestObjectiveTracker", _G.QuestObjectiveTracker)
	Secure("before")
	Measure("before")
	ns.TestPrompt("Tracker height test: stand still, out of combat, 12 sec. Don't touch the tracker.", 12)
	local savedEdit, savedHeight = tracker.editModeHeight, tracker:GetHeight()
	-- (The tracker shown fully for the test, to see it.)
	local savedAlpha = tracker:GetAlpha()
	local function Step(delay, fn)
		C_Timer.After(delay, function()
			if not run then return end
			if InCombatLockdown() then
				Add("combat started: steps skipped, put back")
				tracker.editModeHeight = savedEdit
				pcall(tracker.SetHeight, tracker, savedHeight)
				return
			end
			local ok, err = pcall(fn)
			if not ok then Add("step error: " .. tostring(err)) end
		end)
	end
	Step(1, function()
		tracker:SetAlpha(1)
		Shot()
		Add("screenshot 1: as it is")
		if type(savedEdit) == "number" then
			tracker.editModeHeight = BIG
			Update("A (editModeHeight " .. BIG .. ")")
		else
			Add("A skipped: no editModeHeight")
		end
	end)
	Step(2.5, function()
		Measure("A")
		tracker:SetAlpha(1)
		Shot()
		Add("screenshot 2: A")
		tracker.editModeHeight = savedEdit
		Update("A put back")
	end)
	Step(4, function()
		Measure("A put back")
		tracker:SetHeight(BIG)
		Update("B (SetHeight " .. BIG .. ")")
	end)
	Step(5.5, function()
		Measure("B")
		tracker:SetAlpha(1)
		Shot()
		Add("screenshot 3: B")
		tracker:SetHeight(savedHeight)
		Update("B put back")
	end)
	Step(7, function()
		Measure("B put back")
		Secure("after")
		tracker:SetAlpha(savedAlpha)
		Shot()
		Add("screenshot 4: put back")
		ns.TestPrompt("Now play 3 min: fight, use a quest item if you have one. Blocked actions get logged.", 12)
		run.timer = C_Timer.NewTimer(HEIGHT_PLAY, function()
			if run and run.events then run.events:UnregisterAllEvents() end
			Finish(false)
		end)
	end)
end

function ns.QuestFocusTest(mode)
	if run then
		if run.events then run.events:UnregisterAllEvents() end
		return Finish(true)
	end
	if mode == "height" then return HeightTest() end
	local db = ns.db
	if not db then return end
	db.questFocusLog = {}
	run = { log = db.questFocusLog, start = GetTime(), last = {}, shots = 0 }
	Add(("start: client %s, build %s"):format(ns.isRetail and "retail" or "Forever/Classic",
		tostring((select(4, GetBuildInfo())))))
	local keys = { "questRevealOnProgress", "questRevealOnAccept", "questRevealOnScenario", "questRevealOnlyThat",
		"questRevealCollapse", "questProgressCalm", "questAcceptCalm", "questRevealTime", "calmTime" }
	local settings = {}
	for _, key in ipairs(keys) do settings[#settings + 1] = key .. "=" .. tostring(db[key]) end
	Add("settings: " .. table.concat(settings, ", ") .. ", Quest tracker page on "
		.. tostring(ns.PageOn and ns.PageOn("handleQuests")))
	local loaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
	Add(("addons: Questie %s (Questie_BaseFrame %s), EllesmereUI tracker %s, addon tracker up %s"):format(
		tostring(loaded and loaded("Questie")), Shown(_G.Questie_BaseFrame), Shown(_G.EUI_CustomQuestTracker),
		tostring(ns.QuestTrackerOfAddonUp and ns.QuestTrackerOfAddonUp())))
	Shape("start")
	ns.questFocusRec = Record
	run.timer = C_Timer.NewTimer(LENGTH, function() Finish(false) end)
	ns.TestPrompt("Quest focus test, 4 min: kill mobs for a quest in your tracker (one not in it too, "
		.. "if you can). Don't hover the tracker. Type it again to stop early.", 12)
end
