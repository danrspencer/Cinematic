-- /cine debug turnlag: one run finding what makes turning the camera in a
-- crowd laggy, Cinematic or the game. Hands off: the test turns the camera
-- itself (MoveViewLeftStart at a steady pace), so every turning step is the
-- same. Timed steps in the big test box (Frames.lua's ns.PadTestBox):
--   1 CineMode on, camera still        (the calm baseline)
--   2 CineMode on, camera turning
--   3 CineMode off, camera turning     (the game's own cost, near enough)
--   4 CineMode off, camera still
--   5 CineMode on, turning, with the detailed CPU recording (which parts of
--     Cinematic cost what while turning; it adds its own cost, so this
--     step's frame times aren't compared with the others)
-- Each step logs: frames, average and worst frame time, frames over 33 and
-- 50 ms, Cinematic's ms a frame and all addons' (the game's profiler),
-- memory made a second, nameplates added and taken away a second, and a
-- screenshot. CineMode is put back as it was, the turning stopped, at the
-- end or if a /reload cuts it short. Into CinematicDB.turnLagLog. Dev copy
-- only (CinematicDev.toc).
local _, ns = ...

local SETUP, WAIT = 10, 3 -- seconds: before the first step, settling at each step's start before measuring
local TURN_SPEED = 0.25    -- of the camera's yaw speed: a full turn in about 8 seconds

local run -- { at, step, starts, notes, cine, turning }

local function Say(text)
	local log = CinematicDB and CinematicDB.turnLagLog
	if log then log[#log + 1] = ("%.1f %s"):format(run and GetTime() - run.at or 0, text) end
end

local function Turn(on)
	if on and not run.turning then
		run.turning = true
		CinematicDB.turnLagTurning = true
		pcall(MoveViewLeftStart, TURN_SPEED)
	elseif not on and run.turning then
		run.turning = false
		CinematicDB.turnLagTurning = nil
		pcall(MoveViewLeftStop)
	end
end
local function CineMode(on)
	if (ns.lastCinematic and true or false) == on then return end
	if run.cine == nil then
		run.cine = ns.lastCinematic and true or false
		CinematicDB.turnLagCine = run.cine
	end
	if Cinematic_ToggleCineMode then pcall(Cinematic_ToggleCineMode) end
end
-- (Cut short by a /reload: the turning stops by itself; CineMode back.)
local restorer = CreateFrame("Frame")
restorer:RegisterEvent("PLAYER_ENTERING_WORLD")
restorer:SetScript("OnEvent", function(self)
	self:UnregisterAllEvents()
	if CinematicDB and CinematicDB.turnLagTurning then
		pcall(MoveViewLeftStop)
		CinematicDB.turnLagTurning = nil
	end
	if CinematicDB and CinematicDB.turnLagCine ~= nil then
		local want = CinematicDB.turnLagCine
		CinematicDB.turnLagCine = nil
		C_Timer.After(3, function()
			if (ns.lastCinematic and true or false) ~= want and Cinematic_ToggleCineMode then pcall(Cinematic_ToggleCineMode) end
		end)
		ns.Print("turn lag test was cut short: CineMode is back as it was")
	end
end)

-- Per frame while a step measures.
local meter = CreateFrame("Frame")
meter:Hide()
local m -- the step's figures
local function GameMs(kind)
	return ns.ProfileGameMetric and ns.ProfileGameMetric(kind, "LastTime") or nil
end
ns.SetOnUpdate(meter, function(_, elapsed)
	if not m then return end
	local ms = elapsed * 1000
	m.frames = m.frames + 1
	m.ms = m.ms + ms
	if ms > m.worst then m.worst = ms end
	if ms > 33 then m.over33 = m.over33 + 1 end
	if ms > 50 then m.over50 = m.over50 + 1 end
	local ours, all = GameMs("addon"), GameMs("overall")
	if ours then
		m.ourFrames = m.ourFrames + 1
		m.ours, m.all = m.ours + ours, m.all + (all or 0)
		if ours > m.ourWorst then m.ourWorst = ours end
	end
	local kb = collectgarbage("count")
	if kb > m.kbLast then m.kbMade = m.kbMade + kb - m.kbLast end
	m.kbLast = kb
end)
local plates = CreateFrame("Frame")
plates:RegisterEvent("NAME_PLATE_UNIT_ADDED")
plates:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
plates:SetScript("OnEvent", function(_, event)
	if not m then return end
	if event == "NAME_PLATE_UNIT_ADDED" then m.added = m.added + 1 else m.removed = m.removed + 1 end
end)
local function Measure()
	m = { at = GetTime(), frames = 0, ms = 0, worst = 0, over33 = 0, over50 = 0, ourFrames = 0, ours = 0, all = 0,
		ourWorst = 0, kbLast = collectgarbage("count"), kbMade = 0, added = 0, removed = 0 }
	meter:Show()
end
local function Result()
	meter:Hide()
	if not m or m.frames == 0 then return "nothing measured" end
	local seconds = math.max(0.1, GetTime() - m.at)
	local line = ("%d frames in %.1f s (%.0f fps): frame %.1f ms average, worst %.0f, over 33 ms %d, over 50 ms %d; "
		.. "Cinematic %.2f ms a frame (worst %.1f), all addons %.2f; memory made %.0f KB a second; plates added %.1f, "
		.. "removed %.1f a second, %d up now"):format(m.frames, seconds, m.frames / seconds, m.ms / m.frames, m.worst,
		m.over33, m.over50, m.ourFrames > 0 and m.ours / m.ourFrames or -1, m.ourWorst,
		m.ourFrames > 0 and m.all / m.ourFrames or -1, m.kbMade / seconds, m.added / seconds, m.removed / seconds,
		#(C_NamePlate and C_NamePlate.GetNamePlates() or {}))
	m = nil
	return line
end
local function Shot(what)
	ns.PadTestBoxHide()
	local ok = pcall(function() Screenshot() end)
	return ("screenshot %s at %s%s"):format(what, date("%m%d%y_%H%M%S"), ok and "" or " (failed)")
end

local STEPS = {
	{ key = "still-cine", seconds = 12, say = "%d/%d: CineMode ON, camera STILL. Hands off.",
		act = function() CineMode(true) Turn(false) end },
	{ key = "turn-cine", seconds = 16, say = "%d/%d: CineMode ON, the test TURNS the camera. Hands off.",
		act = function() CineMode(true) Turn(true) end },
	{ key = "turn-off", seconds = 16, say = "%d/%d: CineMode OFF, the test TURNS the camera. Hands off.",
		act = function() CineMode(false) Turn(true) end },
	{ key = "still-off", seconds = 12, say = "%d/%d: CineMode OFF, camera STILL. Hands off.",
		act = function() CineMode(false) Turn(false) end },
	{ key = "turn-cine-detail", seconds = 19, detail = true,
		say = "%d/%d: CineMode ON, TURNING, with the detailed CPU recording. Hands off.",
		act = function() CineMode(true) Turn(true) end },
}

local function Finish(done)
	if run.ticker then run.ticker:Cancel() end
	meter:Hide()
	m = nil
	Turn(false)
	if run.cine ~= nil then CineMode(run.cine) end
	CinematicDB.turnLagCine = nil
	if ns.IsProfiling and ns.IsProfiling() and run.profiling then ns.StopProfile() end
	for i, step in ipairs(STEPS) do
		local note = run.notes[step.key]
		Say(("verdict %d %s: %s"):format(i, step.key, note and note.found or "not run"))
	end
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
		local last = STEPS[run.step]
		if last and run.notes[last.key] and not run.notes[last.key].found then
			run.notes[last.key].found = Result()
			Say("  " .. run.notes[last.key].found)
		end
		Finish(true)
		return
	end
	local step = STEPS[index]
	local into = now - run.starts[index]
	local note = run.notes[step.key]
	if index ~= run.step then
		-- (The step before: its figures.)
		local before = STEPS[run.step]
		if before and run.notes[before.key] and not run.notes[before.key].found then
			run.notes[before.key].found = Result()
			Say("  " .. run.notes[before.key].found)
		end
		run.step = index
		note = {}
		run.notes[step.key] = note
		local ok, err = pcall(step.act)
		Say(("--- step %d: %s (CineMode %s, plates up %d)%s ---"):format(index, step.key, tostring(ns.lastCinematic),
			#(C_NamePlate and C_NamePlate.GetNamePlates() or {}), ok and "" or (" error: " .. tostring(err))))
	end
	if not note.measuring and into >= WAIT then
		note.measuring = true
		Measure()
		if step.detail and ns.StartProfile then
			run.profiling = ns.StartProfile(step.seconds - WAIT - 1, true, true)
			Say("  detailed recording " .. (run.profiling and "started" or "couldn't start (one running?)"))
		end
	end
	if not note.shot and into >= step.seconds / 2 then
		note.shot = true
		Say("  " .. Shot(("step %d %s"):format(index, step.key)))
		return -- (the box stays hidden for the screenshot)
	end
	ns.PadTestBox(step.say:format(index, #STEPS), into < WAIT and "GET READY"
		or ("RECORDING: %d sec left"):format(math.ceil(step.seconds - into)), into < WAIT and 1 or 0.3,
		into < WAIT and 0.82 or 1, into < WAIT and 0 or 0.3)
end

function ns.TurnLagTest()
	if run then
		Finish(false)
		return
	end
	if InCombatLockdown() then
		ns.Print("turn lag test: not in a fight")
		return
	end
	CinematicDB.turnLagLog = {}
	run = { at = GetTime(), step = 0, notes = {}, starts = {} }
	local at = SETUP
	for i, step in ipairs(STEPS) do
		run.starts[i] = at
		at = at + step.seconds
	end
	run.starts[#STEPS + 1] = at
	Say(("start: %s (game %s), CineMode %s, Shoulder Cam %s, plates up %d, view distance %s, style theme %s"):format(
		ns.isRetail and "retail" or "classic", tostring((select(4, GetBuildInfo()))), tostring(ns.lastCinematic),
		tostring(ns.db and ns.db.shoulderCam), #(C_NamePlate and C_NamePlate.GetNamePlates() or {}),
		tostring(GetCVar and GetCVar("graphicsViewDistance")), tostring(ns.db and ns.db.styleTheme)))
	run.ticker = C_Timer.NewTicker(0.25, function()
		local ok, err = pcall(Tick)
		if not ok then
			Say("error: " .. tostring(err))
			if run then Finish(false) end
		end
	end)
	ns.Print(("turn lag test: %d sec, hands off, follow the box (type it again to stop)"):format(math.floor(at)))
end
