-- /cine debug platecost: one run finding where the cost of plates goes while
-- the camera turns fast in a crowd (plates coming and going), and what
-- sleeping plates (PlateSleep.lua) save. Hands off: the test turns the camera
-- itself at the turn lag test's fast pace (TurnLagTest.lua), CineMode on
-- unless said. Timed steps in the big test box (Frames.lua's ns.PadTestBox):
--   1 baseline          plates never sleep (as before 2026-11-17)
--   2 sleep, ours       our work skipped on plates showing nothing
--   3 sleep, hide       and the game's frame on them hidden
--   4 sleep, strip      and its events taken away too (given back on waking)
--   5 baseline again    (drift check: crowd moving, warm caches)
--   6 CineMode off      (the game alone, near enough)
-- 2026-11-17's first run (fewer plates by distance, names-only plates, the
-- game's frame stripped by hand): distance didn't cut the count in a city
-- (the 40-plate cap), Forever has no names-only setting, stripping saved ~4 ms.
-- Each step logs: frames, average and worst frame time, frames over 33 and
-- 50 ms, Cinematic's ms a frame, the game's plate add-on's (always 0 on
-- Forever: its profiler doesn't time it), all addons', memory made a second,
-- plates added and taken away a second, plates up on average, plates slept
-- and woken, and a screenshot. At the end, verdicts against the baseline.
-- CineMode and the sleep mode are put back at the end, or after a /reload
-- that cuts it short. Into CinematicDB.plateCostLog. Dev copy only
-- (CinematicDev.toc).
local _, ns = ...

local SETUP, WAIT = 10, 3 -- seconds: before the first step, settling at each step's start before measuring
local FAST = 2 -- of the camera's yaw speed: about a turn a second (TurnLagTest.lua's FAST)
local STEP_SECONDS = 14
-- (Where the game's own plate code is an add-on the profiler may report.)
local PLATE_ADDONS = { "Blizzard_NamePlates", "Blizzard_Nameplates" }

local run -- { at, step, starts, notes, cine, turning, mode }

local function Say(text)
	local log = CinematicDB and CinematicDB.plateCostLog
	if log then log[#log + 1] = ("%.1f %s"):format(run and GetTime() - run.at or 0, text) end
end

local function Turn(speed)
	if speed and run.turning ~= speed then
		if run.turning then pcall(MoveViewLeftStop) end
		run.turning = speed
		CinematicDB.plateCostTurning = true
		pcall(MoveViewLeftStart, speed)
	elseif not speed and run.turning then
		run.turning = false
		CinematicDB.plateCostTurning = nil
		pcall(MoveViewLeftStop)
	end
end
local function CineMode(on)
	if (ns.lastCinematic and true or false) == on then return end
	if run.cine == nil then
		run.cine = ns.lastCinematic and true or false
		CinematicDB.plateCostCine = run.cine
	end
	if Cinematic_ToggleCineMode then pcall(Cinematic_ToggleCineMode) end
end

-- (Game settings an older run of this test changed, put back.)
local function PutBackCVars()
	local saved = CinematicDB and CinematicDB.plateCostCVars
	if not saved then return end
	for name, value in pairs(saved) do
		pcall(SetCVar, name, value)
		Say(("  %s back to %s (reads %s)"):format(name, tostring(value), tostring(GetCVar(name))))
	end
	CinematicDB.plateCostCVars = nil
end

-- (Cut short by a /reload: the turning stops by itself; settings and
-- CineMode back.)
local restorer = CreateFrame("Frame")
restorer:RegisterEvent("PLAYER_ENTERING_WORLD")
restorer:SetScript("OnEvent", function(self)
	self:UnregisterAllEvents()
	if not CinematicDB then return end
	local cut = false
	if CinematicDB.plateCostTurning then
		pcall(MoveViewLeftStop)
		CinematicDB.plateCostTurning = nil
		cut = true
	end
	if CinematicDB.plateCostCVars then
		for name, value in pairs(CinematicDB.plateCostCVars) do pcall(SetCVar, name, value) end
		CinematicDB.plateCostCVars = nil
		cut = true
	end
	if CinematicDB.plateCostCine ~= nil then
		local want = CinematicDB.plateCostCine
		CinematicDB.plateCostCine = nil
		cut = true
		C_Timer.After(3, function()
			if (ns.lastCinematic and true or false) ~= want and Cinematic_ToggleCineMode then pcall(Cinematic_ToggleCineMode) end
		end)
	end
	if cut then ns.Print("plate cost test was cut short: settings and CineMode are back as they were") end
end)

-- The game's profiler: one add-on's ms this frame (nil if it won't say).
local function MetricId()
	local metrics = Enum and Enum.AddOnProfilerMetric
	return metrics and metrics.LastTime
end
local function AddOnMs(name)
	local profiler, id = C_AddOnProfiler, MetricId()
	if not (profiler and profiler.GetAddOnMetric and id) then return nil end
	local ok, value = pcall(profiler.GetAddOnMetric, name, id)
	if ok and type(value) == "number" and not (issecretvalue and issecretvalue(value)) then return value end
	return nil
end
-- Which of PLATE_ADDONS the profiler answers for (found once).
local plateAddOn
local function PlateAddOnMs()
	if plateAddOn == nil then
		plateAddOn = false
		for _, name in ipairs(PLATE_ADDONS) do
			if AddOnMs(name) ~= nil then plateAddOn = name break end
		end
	end
	return plateAddOn and AddOnMs(plateAddOn) or nil
end

local function PlateCount()
	return #(C_NamePlate and C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlates() or {})
end

-- Per frame while a step measures.
local meter = CreateFrame("Frame")
meter:Hide()
local m -- the step's figures
ns.SetOnUpdate(meter, function(_, elapsed)
	if not m then return end
	local ms = elapsed * 1000
	m.frames = m.frames + 1
	m.ms = m.ms + ms
	if ms > m.worst then m.worst = ms end
	if ms > 33 then m.over33 = m.over33 + 1 end
	if ms > 50 then m.over50 = m.over50 + 1 end
	local ours = ns.ProfileGameMetric and ns.ProfileGameMetric("addon", "LastTime")
	if ours then
		m.ourFrames = m.ourFrames + 1
		m.ours = m.ours + ours
		m.all = m.all + (ns.ProfileGameMetric("overall", "LastTime") or 0)
	end
	local blizz = PlateAddOnMs()
	if blizz then
		m.blizzFrames = m.blizzFrames + 1
		m.blizz = m.blizz + blizz
	end
	m.platesSum = m.platesSum + PlateCount()
	local kb = collectgarbage("count")
	if kb > m.kbLast then m.kbMade = m.kbMade + kb - m.kbLast end
	m.kbLast = kb
end)
local plateEvents = CreateFrame("Frame")
plateEvents:RegisterEvent("NAME_PLATE_UNIT_ADDED")
plateEvents:RegisterEvent("NAME_PLATE_UNIT_REMOVED")

plateEvents:SetScript("OnEvent", function(_, event)
	if m then
		if event == "NAME_PLATE_UNIT_ADDED" then m.added = m.added + 1 else m.removed = m.removed + 1 end
	end
end)

local function Measure()
	m = { at = GetTime(), frames = 0, ms = 0, worst = 0, over33 = 0, over50 = 0, ourFrames = 0, ours = 0, all = 0,
		blizzFrames = 0, blizz = 0, platesSum = 0, kbLast = collectgarbage("count"), kbMade = 0, added = 0, removed = 0 }
	meter:Show()
end
-- The step's figures: a line for the log and the numbers for the verdicts.
local function Result()
	meter:Hide()
	if not m or m.frames == 0 then
		m = nil
		return "nothing measured"
	end
	local seconds = math.max(0.1, GetTime() - m.at)
	local figures = {
		fps = m.frames / seconds, frame = m.ms / m.frames, worst = m.worst,
		ours = m.ourFrames > 0 and m.ours / m.ourFrames or nil,
		all = m.ourFrames > 0 and m.all / m.ourFrames or nil,
		blizz = m.blizzFrames > 0 and m.blizz / m.blizzFrames or nil,
		added = m.added / seconds, plates = m.platesSum / m.frames,
	}
	local function Ms(value) return value and ("%.2f"):format(value) or "n/a" end
	local line = ("%d frames in %.1f s (%.0f fps): frame %.1f ms average, worst %.0f, over 33 ms %d, over 50 ms %d; "
		.. "Cinematic %s ms a frame, game plate code (%s) %s, all addons %s; memory made %.0f KB a second; "
		.. "plates added %.1f, removed %.1f a second, %.1f up on average"):format(m.frames, seconds, figures.fps,
		figures.frame, m.worst, m.over33, m.over50, Ms(figures.ours), plateAddOn or "not reported", Ms(figures.blizz),
		Ms(figures.all), m.kbMade / seconds, figures.added, m.removed / seconds, figures.plates)
	m = nil
	return line, figures
end
local function Shot(what)
	ns.PadTestBoxHide()
	local ok = pcall(function() Screenshot() end)
	return ("screenshot %s at %s%s"):format(what, date("%m%d%y_%H%M%S"), ok and "" or " (failed)")
end

-- Sleeping plates' modes (PlateSleep.lua), set for a step: every plate
-- woken first so the step starts clean.
local function Mode(mode)
	local sleep = ns.plateSleep
	if not sleep then return "skipped: no plate sleep here" end
	if run.mode == nil then run.mode = sleep.mode end
	sleep.mode = mode
	sleep.WakeAll()
	Say("  plate sleep mode " .. mode)
end
local function SleepCounts()
	if ns.plateSleep then Say("  " .. ns.plateSleep.Describe()) end
	-- (Friendly players' plates: CineMode turns them on only where a row wants them.)
	local set = ns.plates and ns.plates.FRIEND_PLAYER_CVARS
	Say(("  friendly player plates: game setting %s, held on by CineMode %s, yours %s"):format(
		tostring(GetCVar("nameplateShowFriendlyPlayers")), tostring(set and set.active or false),
		tostring(ns.db.savedCVars and ns.db.savedCVars.nameplateShowFriendlyPlayers)))
end

local STEPS = {
	{ key = "baseline", say = "%d/%d: CineMode ON, plates NOT sleeping (as before). Turning FAST. Hands off.",
		act = function() CineMode(true) Turn(FAST) return Mode("off") end, undo = SleepCounts },
	{ key = "sleep-ours", say = "%d/%d: CineMode ON, plates SLEEP (our work only). Turning FAST. Hands off.",
		act = function() CineMode(true) Turn(FAST) return Mode("ours") end, undo = SleepCounts },
	{ key = "sleep-hide", say = "%d/%d: CineMode ON, plates SLEEP (game frame hidden). Turning FAST. Hands off.",
		act = function() CineMode(true) Turn(FAST) return Mode("hide") end, undo = SleepCounts },
	{ key = "sleep-strip", say = "%d/%d: CineMode ON, plates SLEEP (game frame hidden, no events). Turning FAST. Hands off.",
		act = function() CineMode(true) Turn(FAST) return Mode("strip") end, undo = SleepCounts },
	{ key = "baseline-again", say = "%d/%d: CineMode ON, plates NOT sleeping, again. Turning FAST. Hands off.",
		act = function() CineMode(true) Turn(FAST) return Mode("off") end, undo = SleepCounts },
	{ key = "cinemode-off", say = "%d/%d: CineMode OFF, turning FAST. Hands off.",
		act = function() Mode("hide") CineMode(false) Turn(FAST) end, undo = SleepCounts },
}

-- Each step against the two baselines' average: frame time and fps.
local function Verdicts()
	local base1, base2 = run.notes.baseline, run.notes["baseline-again"]
	local b1, b2 = base1 and base1.figures, base2 and base2.figures
	local base = b1 and b2 and (b1.frame + b2.frame) / 2 or (b1 or b2) and (b1 or b2).frame
	if b1 and b2 then
		Say(("verdict drift: baseline %.1f ms then %.1f ms a frame (%.0f%% apart%s)"):format(b1.frame, b2.frame,
			math.abs(b1.frame - b2.frame) / math.max(b1.frame, b2.frame) * 100,
			math.abs(b1.frame - b2.frame) / math.max(b1.frame, b2.frame) > 0.15 and ": crowd changed, read the rest loosely"
				or ""))
	end
	for i, step in ipairs(STEPS) do
		local note = run.notes[step.key]
		local f = note and note.figures
		if note and note.skipped then
			Say(("verdict %d %s: %s"):format(i, step.key, note.skipped))
		elseif not f then
			Say(("verdict %d %s: not run"):format(i, step.key))
		elseif base and not step.key:find("^baseline") then
			local saved = base - f.frame
			Say(("verdict %d %s: %.1f ms a frame vs baseline %.1f (%s%.1f ms, %.0f fps), %.1f plates up, %.1f added a second; "
				.. "Cinematic %s ms, game plate code %s ms"):format(i, step.key, f.frame, base, saved >= 0 and "saves " or "costs ",
				math.abs(saved), f.fps, f.plates, f.added, f.ours and ("%.2f"):format(f.ours) or "n/a",
				f.blizz and ("%.2f"):format(f.blizz) or "n/a"))
		else
			Say(("verdict %d %s: %.1f ms a frame (%.0f fps), %.1f plates up, %.1f added a second; Cinematic %s ms, "
				.. "game plate code %s ms"):format(i, step.key, f.frame, f.fps, f.plates, f.added,
				f.ours and ("%.2f"):format(f.ours) or "n/a", f.blizz and ("%.2f"):format(f.blizz) or "n/a"))
		end
	end
end

local function EndStep(index)
	local step = STEPS[index]
	local note = step and run.notes[step.key]
	if not note or note.ended then return end
	note.ended = true
	if not note.skipped then
		local line, figures = Result()
		note.figures = figures
		Say("  " .. line)
	end
	if step.undo then pcall(step.undo) end
end

local function Finish(done)
	if run.ticker then run.ticker:Cancel() end
	EndStep(run.step)
	meter:Hide()
	m = nil
	Turn(nil)
	PutBackCVars()
	if run.cine ~= nil then CineMode(run.cine) end
	CinematicDB.plateCostCine = nil
	if ns.plateSleep and run.mode then
		ns.plateSleep.mode = run.mode
		ns.plateSleep.WakeAll()
	end
	Verdicts()
	run = nil
	ns.PadTestBox(done and "Test done. /reload, then say \"check log\"." or "Test stopped.", "", 1, 0.82, 0)
	C_Timer.After(12, function() if not run then ns.PadTestBoxHide() end end)
end

local function Tick()
	local now = GetTime() - run.at
	if InCombatLockdown() then
		Say("stopped: a fight started")
		Finish(false)
		return
	end
	if now < SETUP then
		ns.PadTestBox("Stand in the BUSIEST spot (lots of players), out of a fight. Then HANDS OFF the mouse and " ..
			"keyboard: the test turns the camera and switches CineMode by itself.",
			("Starts in %d"):format(math.ceil(SETUP - now)), 1, 0.82, 0)
		return
	end
	local index
	for i = #run.starts, 1, -1 do
		if now >= run.starts[i] then index = i break end
	end
	if index > #STEPS then
		Finish(true)
		return
	end
	local step = STEPS[index]
	local into = now - run.starts[index]
	local note = run.notes[step.key]
	if index ~= run.step then
		EndStep(run.step)
		run.step = index
		note = {}
		run.notes[step.key] = note
		local ok, skipped = pcall(step.act)
		if ok and type(skipped) == "string" then note.skipped = skipped end
		Say(("--- step %d: %s (CineMode %s, plates up %d)%s ---"):format(index, step.key, tostring(ns.lastCinematic),
			PlateCount(), ok and (note.skipped and (" " .. note.skipped) or "") or (" error: " .. tostring(skipped))))
	end
	if not note.skipped and not note.measuring and into >= WAIT then
		note.measuring = true
		Measure()
	end
	if not note.skipped and not note.shot and into >= STEP_SECONDS / 2 then
		note.shot = true
		Say("  " .. Shot(("step %d %s"):format(index, step.key)))
		return -- (the box stays hidden for the screenshot)
	end
	ns.PadTestBox(step.say:format(index, #STEPS), into < WAIT and "GET READY"
		or ("RECORDING: %d sec left"):format(math.ceil(STEP_SECONDS - into)), into < WAIT and 1 or 0.3,
		into < WAIT and 0.82 or 1, into < WAIT and 0 or 0.3)
end

function ns.PlateCostTest()
	if run then
		Finish(false)
		return
	end
	if InCombatLockdown() then
		ns.Print("plate cost test: not in a fight")
		return
	end
	CinematicDB.plateCostLog = {}
	run = { at = GetTime(), step = 0, notes = {}, starts = {} }
	local at = SETUP
	for i = 1, #STEPS do
		run.starts[i] = at
		at = at + STEP_SECONDS
	end
	run.starts[#STEPS + 1] = at
	plateAddOn = nil
	local loaded = {}
	for _, name in ipairs(PLATE_ADDONS) do
		local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded and select(1, C_AddOns.IsAddOnLoaded(name))
		loaded[#loaded + 1] = ("%s loaded %s, profiler %s"):format(name, tostring(isLoaded),
			AddOnMs(name) ~= nil and "reports it" or "silent")
	end
	Say(("start: %s (game %s), CineMode %s, plates up %d, nameplateMaxDistance %s, nameplateShowOnlyNames %s, "
		.. "nameplateShowOffscreen %s, NamePlateDriverFrame %s; %s"):format(ns.isRetail and "retail" or "classic",
		tostring((select(4, GetBuildInfo()))), tostring(ns.lastCinematic), PlateCount(),
		tostring(GetCVar("nameplateMaxDistance")), tostring(GetCVar("nameplateShowOnlyNames")),
		tostring(GetCVar("nameplateShowOffscreen")), _G.NamePlateDriverFrame and "found" or "not found",
		table.concat(loaded, "; ")))
	run.ticker = C_Timer.NewTicker(0.25, function()
		local ok, err = pcall(Tick)
		if not ok then
			Say("error: " .. tostring(err))
			if run then Finish(false) end
		end
	end)
	ns.Print(("plate cost test: %d sec, hands off, follow the box (type it again to stop)"):format(math.floor(at)))
end
