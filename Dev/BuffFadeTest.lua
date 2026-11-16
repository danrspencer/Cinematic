-- /cine debug bufftest: one run recording why a buff icon's picture can stay
-- hidden after a buff peek's "Just the new one" fade (a player saw the
-- timers and tooltips come back on hover, not the pictures, till a reload).
-- That option fades each other icon's parts on their own (Frames.lua
-- FadeParts) and puts back the alpha it saved for each (ns.UnfadeBuffIcon).
-- Four timed steps in the big test box (ns.PadTestBox), each a way a peek
-- can end: on its own, by a hover, by a fight, and by BuffFrame being let
-- go mid-peek (Standard Frames off). The log ("bufftest", its own list
-- CinematicDB.buffTestLog) gets each icon's parts whenever they change, the
-- saved alphas, every ShowOnlyNewBuffs turn and UnfadeBuffIcon call, and a
-- STUCK line for any icon shown at a hover with its picture under half.
-- Screenshots as each hover starts and 2 sec on. Steps as arguments
-- ("bufftest 3 4") redo only those. Dev copy only (CinematicDev.toc).
local ADDON_NAME, ns = ...

local LOG_MAX = 4000
local READY = 4 -- seconds to read each step before it records

local run -- { at, step, steps, stepAt, ticker, last, stuck, hoverSeen, kept, orig }

local function Readable(value)
	return type(value) == "number" and not (issecretvalue and issecretvalue(value))
end
local function Num(value)
	if value == nil then return "nil" end
	if issecretvalue and issecretvalue(value) then return "secret" end
	if type(value) == "number" then return ("%.2f"):format(value) end
	return tostring(value)
end

local function Log(text)
	local db = ns.db
	if not db then return end
	local log = db.buffTestLog
	if type(log) ~= "table" then
		log = {}
		db.buffTestLog = log
	end
	if #log < LOG_MAX then
		log[#log + 1] = ("%.1fs %s"):format(run and GetTime() - run.at or 0, text)
	end
end

-- (Wrapped: C_Timer refused the game's Screenshot itself on WoW Forever.)
local function Shot() Screenshot() end

-- A button's name for the log: its global name, else its place in the row.
local function NameOf(button, place)
	local ok, name = pcall(button.GetName, button)
	return ok and name or ("icon" .. tostring(place))
end

-- A button's parts by role: picture, timer, count, border.
local function Parts(button)
	local name = NameOf(button)
	local function Get(key, suffix)
		return button[key] or (type(name) == "string" and _G[name .. suffix]) or nil
	end
	return Get("Icon", "Icon"), Get("Duration", "Duration"), Get("Count", "Count"),
		button.Border or button.DebuffBorder or (type(name) == "string" and _G[name .. "Border"]) or nil
end

local function AlphaOf(part)
	if not part then return nil end
	local ok, alpha = pcall(part.GetAlpha, part)
	return ok and alpha or nil
end

local function BuffEntry()
	for _, entry in ipairs(ns.managed or {}) do
		if entry.name == "BuffFrame" then return entry end
	end
end

-- Every icon now: its line for the log, and whether it's shown with its
-- picture under half (stuck), the button itself drawn.
local function Look(fn)
	local place = 0
	ns.ForEachBuffIcon(function(button)
		place = place + 1
		local okShown, shown = pcall(button.IsVisible, button)
		shown = okShown and shown == true
		local picture, timer, count, border = Parts(button)
		local saved = ns.newBuffFaded[button]
		local pictureAlpha = AlphaOf(picture)
		local okEff, effective = pcall(button.GetEffectiveAlpha, button)
		local okIcon, icon = pcall(ns.BuffIconOf, button)
		local line = ("%s shown %s, alpha %s, effective %s | picture %s (saved %s) timer %s (saved %s) " ..
			"count %s border %s | fade level %s, on faded list %s, file %s"):format(NameOf(button, place),
			tostring(shown), Num(AlphaOf(button)), okEff and Num(effective) or "?",
			Num(pictureAlpha), Num(saved and picture and saved[picture]), Num(AlphaOf(timer)),
			Num(saved and timer and saved[timer]), Num(AlphaOf(count)), Num(AlphaOf(border)),
			Num(ns.newBuffFadeLevel[button]), tostring(saved ~= nil), okIcon and Num(icon) or "?")
		local stuck = shown and Readable(pictureAlpha) and pictureAlpha < 0.5
			and okEff and Readable(effective) and effective > 0.5
		fn(button, place, line, stuck, pictureAlpha, saved and picture and saved[picture])
	end)
end

local function Hovering()
	local over = false
	ns.ForEachBuffIcon(function(button)
		local ok, isOver = pcall(button.IsMouseOver, button)
		if ok and isOver == true then over = true end
	end)
	local frame = _G.BuffFrame
	if not over and frame and frame.IsMouseOver then
		local ok, isOver = pcall(frame.IsMouseOver, frame)
		over = ok and isOver == true
	end
	return over
end

-- The steps: each a list of phases { till = seconds into the step, say = ..., hover = true when
-- this phase checks the icons, act = fn once as it starts }. A phase with
-- untilCalm waits for the fight to end (up to its till).
local STEPS = {
	{ name = "peek ends on its own", phases = {
		{ till = 5, say = "1/4: CAST A BUFF ON YOURSELF now (any one)" },
		{ till = 20, say = "1/4: HANDS OFF. Keep the mouse away from your buffs, let them fade" },
		{ till = 28, say = "1/4: HOVER your buff icons now (top right)", hover = true },
	} },
	{ name = "hover during the peek", phases = {
		{ till = 4, say = "2/4: CAST A BUFF ON YOURSELF now" },
		{ till = 9, say = "2/4: HOVER your buff icons now, while it peeks", hover = true },
		{ till = 20, say = "2/4: MOVE THE MOUSE AWAY from the buffs, let them fade" },
		{ till = 27, say = "2/4: HOVER your buff icons again", hover = true },
	} },
	-- (Its peek lasts 10 sec, to get in a fight while it's still up: a peek
	-- can't start in one.)
	{ name = "a fight during the peek", peekTime = 10, phases = {
		{ till = 4, say = "3/4: Stand next to a mob or dummy. CAST A BUFF ON YOURSELF now" },
		{ till = 10, say = "3/4: ATTACK the mob or dummy NOW, the buffs are still peeking" },
		{ till = 70, untilCalm = true, say = "3/4: FINISH THE FIGHT, keep the mouse off your buffs" },
		{ till = 78, say = "3/4: Out of combat: HOVER your buff icons now", hover = true },
	} },
	-- (Standard Frames off lets BuffFrame go (RemoveFrame), as does an
	-- addon's support taking the buffs over: kept off through the hover, as
	-- a player's would be, then back on to see whether that brings them back.)
	{ name = "BuffFrame let go during the peek (Standard Frames off)", phases = {
		{ till = 4, say = "4/4: CAST A BUFF ON YOURSELF now" },
		{ till = 6, say = "4/4: Hands off: the test turns Standard Frames OFF", act = function()
			Log("act: Standard Frames off (handleFrames false)")
			ns.db.handleFrames = false
		end },
		{ till = 14, say = "4/4: HOVER your buff icons now (Standard Frames is off)", hover = true },
		{ till = 22, say = "4/4: Hands off: Standard Frames back ON, watch the buffs", act = function()
			Log("act: Standard Frames back on (handleFrames " .. tostring(run.kept.handleFrames) .. ")")
			ns.db.handleFrames = run.kept.handleFrames
		end },
	} },
}

local function StepVerdict(index)
	local stuck = run.stuck[index]
	if not run.hoverSeen[index] then return ("step %d: no hover seen, can't tell"):format(index) end
	local note = ""
	if STEPS[index].peekTime then
		note = run.foughtFaded[index] and ", the fight started with icons faded"
			or ", BUT the fight never started while icons were faded: redo this step"
	end
	if not stuck then return ("step %d OK (%s%s)"):format(index, STEPS[index].name, note) end
	return ("step %d STUCK (%s%s): %s"):format(index, STEPS[index].name, note, stuck)
end

local Finish

local function Tick()
	local now = GetTime()
	local step = STEPS[run.steps[run.step]]
	local index = run.steps[run.step]
	local into = now - run.stepAt - READY
	-- The icons and the frame, logged when they change.
	local entry = BuffEntry()
	local fadedCount = 0
	for _ in pairs(ns.newBuffFaded) do fadedCount = fadedCount + 1 end
	if fadedCount > 0 and InCombatLockdown() and not run.foughtFaded[index] then
		run.foughtFaded[index] = true
		Log(("fight started with %d icons faded"):format(fadedCount))
	end
	local head = ("CineMode %s | page %s, peek %s for %s sec, just new %s, close gaps %s | BuffFrame managed %s, fade %s, " ..
		"icons faded %d | combat %s | hovering %s"):format(tostring(ns.lastCinematic and true or false),
		tostring(ns.db.handleBuffs), tostring(ns.db.buffPeek), Num(ns.db.buffPeekTime), tostring(ns.db.buffPeekOnlyNew),
		tostring(ns.db.buffPeekCollapse), tostring(entry ~= nil), entry and Num(entry.alpha) or "-", fadedCount,
		tostring(InCombatLockdown()), tostring(Hovering()))
	if head ~= run.lastHead then
		run.lastHead = head
		Log(head)
	end
	local phase, phaseIndex
	if into >= 0 then
		for i, p in ipairs(step.phases) do
			if into < p.till or i == #step.phases then
				phase, phaseIndex = p, i
				break
			end
		end
		-- (Wait out the fight: the phase after starts as you leave it.)
		if phase and phase.untilCalm and not InCombatLockdown() and run.fought then
			run.stepAt = now - READY - phase.till
			into = phase.till
			phase, phaseIndex = step.phases[phaseIndex + 1], phaseIndex + 1
		end
		if InCombatLockdown() then run.fought = true end
	end
	Look(function(button, place, line, stuck, pictureAlpha, savedAlpha)
		run.last[button] = run.last[button] or ""
		if line ~= run.last[button] then
			run.last[button] = line
			Log("  " .. line)
		end
		-- (Stuck only when it lasts: the first tick of a hover can read a
		-- picture the addon puts back on its own next frame.)
		if stuck then
			run.stuckSince[button] = run.stuckSince[button] or now
		else
			run.stuckSince[button] = nil
		end
		if phase and phase.hover and Hovering() then
			run.hoverSeen[index] = true
			if stuck and now - run.stuckSince[button] >= 0.5 and not run.stuck[index] then
				run.stuck[index] = ("%s picture alpha %s, saved %s, on faded list %s, fade level %s, BuffFrame managed %s"):format(
					NameOf(button, place), Num(pictureAlpha), Num(savedAlpha), tostring(ns.newBuffFaded[button] ~= nil),
					Num(ns.newBuffFadeLevel[button]), tostring(entry ~= nil))
				Log("STUCK step " .. index .. ": " .. run.stuck[index])
			end
		end
	end)
	-- The box.
	if into < 0 then
		ns.PadTestBox(step.phases[1].say, ("GET READY: starts in %d"):format(math.ceil(-into)), 1, 0.82, 0)
		return
	end
	if phaseIndex ~= run.phaseIndex then
		run.phaseIndex = phaseIndex
		Log(("step %d phase %d: %s"):format(index, phaseIndex, phase.say))
		-- (The step's own peek time, else yours: set as it starts.)
		if phaseIndex == 1 then ns.db.buffPeekTime = step.peekTime or run.kept.buffPeekTime end
		if phase.act then phase.act() end
		if phase.hover then
			Shot()
			C_Timer.After(2, function()
				if run then
					Log(("screenshot: step %d phase %d, 2 sec on"):format(index, phaseIndex))
					Shot()
				end
			end)
			Log(("screenshot: step %d phase %d start"):format(index, phaseIndex))
		end
	end
	local left = math.max(0, math.ceil(phase.till - into))
	local sub = phase.untilCalm and ("RECORDING: in combat %s, %d sec at most"):format(
		tostring(InCombatLockdown()), left) or ("RECORDING: %d sec left"):format(left)
	if not ns.lastCinematic then
		ns.PadTestBox("Turn CineMode ON first", "(the test waits for it)", 1, 0.3, 0.3)
		run.stepAt = now - READY
		run.phaseIndex = nil
		return
	end
	ns.PadTestBox(phase.say, sub, 0.3, 1, 0.3)
	if into >= step.phases[#step.phases].till then
		Log(StepVerdict(index))
		run.step, run.stepAt, run.phaseIndex, run.fought = run.step + 1, now, nil, nil
		if run.step > #run.steps then Finish(true) end
	end
end

Finish = function(done)
	run.ticker:Cancel()
	local verdicts = {}
	for _, index in ipairs(run.steps) do verdicts[#verdicts + 1] = StepVerdict(index) end
	local verdict = table.concat(verdicts, " | ")
	Log("verdict " .. verdict)
	-- (Put back what the test set, and the wrapped functions.)
	for key, value in pairs(run.kept) do ns.db[key] = value end
	ns.ShowOnlyNewBuffs, ns.UnfadeBuffIcon = run.orig.show, run.orig.unfade
	run = nil
	ns.Print("buff fade test: " .. verdict)
	ns.Print("type /reload to save the log, then say check log")
	ns.PadTestBox(done and "Test done. Type /reload, then say check log" or "Test stopped. Type /reload", verdict, 1, 0.82, 0)
	C_Timer.After(20, function() if not run then ns.PadTestBoxHide() end end)
end

-- Typed again while running: stops. only: "3 4" for just those steps.
function ns.BuffFadeTest(only)
	if run then
		Finish(false)
		return
	end
	local steps = {}
	for number in tostring(only or ""):gmatch("%d+") do
		number = tonumber(number)
		if STEPS[number] then steps[#steps + 1] = number end
	end
	if #steps == 0 then steps = { 1, 2, 3, 4 } end
	ns.db.buffTestLog = {}
	run = { at = GetTime(), step = 1, steps = steps, stepAt = GetTime(), last = {}, stuck = {}, hoverSeen = {}, stuckSince = {}, foughtFaded = {},
		kept = {}, orig = { show = ns.ShowOnlyNewBuffs, unfade = ns.UnfadeBuffIcon } }
	-- (What the test needs, put back at the end. Peek time: per step, Tick.)
	run.kept.buffPeekTime = ns.db.buffPeekTime
	for key, value in pairs({ handleFrames = true, handleBuffs = true, buffPeek = true, buffPeekOnlyNew = true, buffPeekIgnoreSelf = false }) do
		run.kept[key] = ns.db[key]
		ns.db[key] = value
	end
	-- (Every turn of "just the new one" and every put-back, logged.)
	local orig = run.orig
	ns.ShowOnlyNewBuffs = function(onlyNew)
		if run and onlyNew ~= run.lastOnly then
			run.lastOnly = onlyNew
			Log("ShowOnlyNewBuffs(" .. tostring(onlyNew) .. ")")
		end
		return orig.show(onlyNew)
	end
	ns.UnfadeBuffIcon = function(button)
		if run then
			local picture = Parts(button)
			local saved = ns.newBuffFaded[button]
			Log(("UnfadeBuffIcon %s: picture now %s, put back to %s"):format(NameOf(button, "?"), Num(AlphaOf(picture)),
				Num(saved and picture and saved[picture])))
		end
		return orig.unfade(button)
	end
	local addons = {}
	for _, name in ipairs({ "ElvUI", "EllesmereUI", "BuffTimers", "Masque", "SexyMap", "BasicMinimap", "Raven", "WeakAuras" }) do
		if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(name) then addons[#addons + 1] = name end
	end
	local okVersion, version = pcall(C_AddOns.GetAddOnMetadata, ADDON_NAME, "Version")
	Log(("start: steps %s, version %s, build %s, client %s, other addons: %s, fade out %s, peek time %s, close gaps %s"):format(
		table.concat(steps, " "), okVersion and tostring(version) or "?", tostring((select(4, GetBuildInfo()))),
		ns.isRetail and "retail" or "not retail",
		#addons > 0 and table.concat(addons, ", ") or "none", Num(ns.db.fadeOutTime), Num(ns.db.buffPeekTime),
		tostring(ns.db.buffPeekCollapse)))
	run.ticker = C_Timer.NewTicker(0.2, function()
		local ok, err = pcall(Tick)
		if not ok then
			Log("error: " .. tostring(err))
			if run then Finish(false) end
		end
	end)
	ns.Print("buff fade test: follow the box (type it again to stop)")
end
