-- /cine debug friendplates: one run checking friendly players' plates since
-- CineMode stopped forcing them all on (6930a24, 2026-11-17: the setting
-- nameplateShowFriendlyPlayers held only where a row wants it, or your target
-- is a friendly player). In a busy city, CineMode on, steps in the big test
-- box (Frames.lua's ns.PadTestBox), each waiting for what it asks of you:
--   1 no target      clear your target; hands off, the camera turns fast:
--                    the setting off, no friendly player plates, no game
--                    names over heads (their name setting held off)
--   2 friend target  target a friendly PLAYER; hands off, the camera turns
--                    fast: the setting on, their plate up with its name
--                    showing, and what turning costs meanwhile
--   3 cleared        clear your target: the setting lets go, plates go
--   4 group          only while you're in a group: each member near you
--                    has a plate, its name showing (skipped solo)
-- Each check logs PASS or FAIL with what it read, the timed steps frames,
-- ms a frame, fps, Cinematic's ms, plates up and added a second, and a
-- screenshot each (look for names over heads that shouldn't be there).
-- Into CinematicDB.friendPlatesLog. Dev copy only (CinematicDev.toc).
local _, ns = ...

local SETUP = 8 -- seconds before the first step
local FAST = 2 -- of the camera's yaw speed (PlateCostTest.lua's FAST)
local TURN_SECONDS = 12
local SETTLE = 2 -- seconds for the plate setting to follow a target change
local WAIT_MAX = 45 -- seconds a step waits for you before it's skipped
-- (The game's setting for friendly players' names over their heads.)
local FRIEND_NAME_CVAR = "UnitNameFriendlyPlayerName"

local run -- { at, index, phase, phaseAt, notes, cine, turning, pass, fail }

local function Say(text)
	local log = CinematicDB and CinematicDB.friendPlatesLog
	if log then log[#log + 1] = ("%.1f %s"):format(run and GetTime() - run.at or 0, text) end
end
local function Check(what, ok, detail)
	if ok then run.pass = run.pass + 1 else run.fail = run.fail + 1 end
	Say(("  %s %s: %s"):format(ok and "PASS" or "FAIL", what, detail))
end

local function Turn(on)
	if on and not run.turning then
		run.turning = true
		CinematicDB.friendPlatesTurning = true
		pcall(MoveViewLeftStart, FAST)
	elseif not on and run.turning then
		run.turning = false
		CinematicDB.friendPlatesTurning = nil
		pcall(MoveViewLeftStop)
	end
end

-- (Cut short by a /reload: the turning stops.)
local restorer = CreateFrame("Frame")
restorer:RegisterEvent("PLAYER_ENTERING_WORLD")
restorer:SetScript("OnEvent", function(self)
	self:UnregisterAllEvents()
	if CinematicDB and CinematicDB.friendPlatesTurning then
		pcall(MoveViewLeftStop)
		CinematicDB.friendPlatesTurning = nil
	end
end)

local function Plates()
	return C_NamePlate and C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlates() or {}
end
local function Plain(value)
	if issecretvalue and issecretvalue(value) then return nil end
	return value
end
local function Ask(fn, ...)
	local ok, value = pcall(fn, ...)
	return ok and Plain(value) or nil
end
local function UnitOf(plate)
	return plate and (plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit))
end
local function FriendlyPlayer(unit)
	return unit and Ask(UnitIsPlayer, unit) and Ask(UnitIsFriend, "player", unit)
		and not Ask(UnitIsUnit, unit, "player") and true or false
end
local function TargetIsFriendlyPlayer()
	return Ask(UnitExists, "target") and FriendlyPlayer("target") or false
end
-- Friendly players' plates up now: all of them, and those not your target's.
local function FriendPlateCount()
	local all, others = 0, 0
	for _, plate in ipairs(Plates()) do
		local unit = UnitOf(plate)
		if FriendlyPlayer(unit) then
			all = all + 1
			if not Ask(UnitIsUnit, unit, "target") then others = others + 1 end
		end
	end
	return all, others
end
local function SetHeld()
	local set = ns.plates and ns.plates.FRIEND_PLAYER_CVARS
	return set and set.active or false
end
-- (A CVar set by its label: the Names sets, ns.cvarSets.)
local function SetByLabel(label)
	for _, set in ipairs(ns.cvarSets or {}) do
		if set.label == label then return set end
	end
end
local function SettingLine()
	local names = SetByLabel("Names: Friends")
	return ("nameplateShowFriendlyPlayers %s (held on by CineMode %s, yours %s), %s %s (Names: Friends held off %s)"):format(
		tostring(GetCVar("nameplateShowFriendlyPlayers")), tostring(SetHeld()),
		tostring(ns.db.savedCVars and ns.db.savedCVars.nameplateShowFriendlyPlayers), FRIEND_NAME_CVAR,
		tostring(GetCVar(FRIEND_NAME_CVAR)), tostring(names and names.active or false))
end
-- Whether a unit's plate shows its name: the plate's alphas (Effects'
-- PlateAlphas, through /cine debug names' description: alpha/body/name/...).
local function NameShowing(unit, plate)
	if not (plate and ns.DescribePlateNameKept) then return false, "no plate" end
	local ok, text = pcall(ns.DescribePlateNameKept, unit, plate)
	if not ok or type(text) ~= "string" then return false, "unreadable: " .. tostring(text) end
	local alpha, _, name = text:match("alphas=([%d%.%-]+)/([%d%.%-]+)/([%d%.%-]+)")
	alpha, name = tonumber(alpha), tonumber(name)
	local asleep = ns.PlateAsleep and ns.PlateAsleep(plate) or false
	local shown = alpha and name and alpha > 0 and name > 0 and plate:IsShown() and not asleep or false
	return shown, ("plate alpha %s, name share %s, frame shown %s, asleep %s; %s"):format(tostring(alpha),
		tostring(name), tostring(plate:IsShown()), tostring(asleep), text)
end

-- Per frame while a step turns.
local meter = CreateFrame("Frame")
meter:Hide()
local m
ns.SetOnUpdate(meter, function(_, elapsed)
	if not m then return end
	local ms = elapsed * 1000
	m.frames, m.ms = m.frames + 1, m.ms + ms
	if ms > m.worst then m.worst = ms end
	if ms > 50 then m.over50 = m.over50 + 1 end
	local ours = ns.ProfileGameMetric and ns.ProfileGameMetric("addon", "LastTime")
	if ours then m.ourFrames, m.ours = m.ourFrames + 1, m.ours + ours end
	m.platesSum = m.platesSum + #Plates()
	local _, others = FriendPlateCount()
	m.friendSum = m.friendSum + others
end)
local plateEvents = CreateFrame("Frame")
plateEvents:RegisterEvent("NAME_PLATE_UNIT_ADDED")
plateEvents:SetScript("OnEvent", function() if m then m.added = m.added + 1 end end)
local function Measure()
	m = { at = GetTime(), frames = 0, ms = 0, worst = 0, over50 = 0, ourFrames = 0, ours = 0, platesSum = 0,
		friendSum = 0, added = 0 }
	meter:Show()
end
local function Result()
	meter:Hide()
	if not m or m.frames == 0 then
		m = nil
		return "nothing measured"
	end
	local seconds = math.max(0.1, GetTime() - m.at)
	local figures = { frame = m.ms / m.frames, fps = m.frames / seconds, plates = m.platesSum / m.frames,
		friends = m.friendSum / m.frames }
	local line = ("%d frames in %.1f s (%.0f fps): frame %.1f ms average, worst %.0f, over 50 ms %d; Cinematic %s ms a "
		.. "frame; %.1f plates up on average, %.1f of them friendly players not your target; plates added %.1f a second")
		:format(m.frames, seconds, figures.fps, figures.frame, m.worst, m.over50,
		m.ourFrames > 0 and ("%.2f"):format(m.ours / m.ourFrames) or "n/a", figures.plates, figures.friends,
		m.added / seconds)
	m = nil
	return line, figures
end
local function Shot(what)
	ns.PadTestBoxHide()
	local ok = pcall(function() Screenshot() end)
	return ("screenshot %s at %s%s"):format(what, date("%m%d%y_%H%M%S"), ok and "" or " (failed)")
end

-- The group's units near enough for a plate.
local function GroupUnits()
	local units = {}
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
	elseif IsInGroup() then
		for i = 1, GetNumGroupMembers() - 1 do units[#units + 1] = "party" .. i end
	end
	return units
end

-- Each step: what the box asks (and when it's done), whether the camera
-- turns, and its checks once ready (settled) and after turning.
local STEPS = {
	{ key = "no-target", ask = "CLEAR your target (Escape). Then HANDS OFF: the camera turns by itself.",
		ready = function() return not Ask(UnitExists, "target") end, turn = true,
		checks = function()
			Say("  " .. SettingLine())
			Check("setting off with no target", not SetHeld() and GetCVar("nameplateShowFriendlyPlayers") ~= "1",
				SettingLine())
			local all = FriendPlateCount()
			Check("no friendly player plates", all == 0, ("%d up of %d plates"):format(all, #Plates()))
			local names = SetByLabel("Names: Friends")
			Check("no game names over friendly players' heads", GetCVar(FRIEND_NAME_CVAR) ~= "1",
				("%s %s, Names: Friends held off %s (see the screenshot)"):format(FRIEND_NAME_CVAR,
				tostring(GetCVar(FRIEND_NAME_CVAR)), tostring(names and names.active or false)))
		end,
		after = function(figures)
			if figures then
				Check("no friendly player plates while turning", figures.friends < 0.5,
					("%.1f on average"):format(figures.friends))
			end
		end },
	{ key = "friend-target", ask = "TARGET a friendly PLAYER (click one, not an NPC). Then HANDS OFF: the camera turns.",
		ready = TargetIsFriendlyPlayer, turn = true,
		checks = function()
			Say("  " .. SettingLine())
			Say(("  target: %s"):format(tostring(Ask(UnitName, "target"))))
			Check("setting on for a friendly player target", SetHeld() and GetCVar("nameplateShowFriendlyPlayers") == "1",
				SettingLine())
			local plate = C_NamePlate.GetNamePlateForUnit and Ask(C_NamePlate.GetNamePlateForUnit, "target")
			Check("your target has a plate", plate ~= nil, plate and "yes" or "none (too far?)")
			if plate then
				local shown, detail = NameShowing("target", plate)
				Check("your target's name shows on its plate", shown, detail)
			end
		end,
		after = function()
			local plate = C_NamePlate.GetNamePlateForUnit and Ask(C_NamePlate.GetNamePlateForUnit, "target")
			if TargetIsFriendlyPlayer() and plate then
				local shown, detail = NameShowing("target", plate)
				Check("your target's name still shows after turning", shown, detail)
			else
				Say("  (target gone or out of view after turning: not checked again)")
			end
		end },
	{ key = "cleared", ask = "CLEAR your target (Escape). Stay still.",
		ready = function() return not Ask(UnitExists, "target") end,
		checks = function()
			Say("  " .. SettingLine())
			Check("setting lets go once the target's cleared", not SetHeld()
				and GetCVar("nameplateShowFriendlyPlayers") ~= "1", SettingLine())
			local all = FriendPlateCount()
			Check("friendly player plates gone", all == 0, ("%d up of %d plates"):format(all, #Plates()))
		end },
	{ key = "group", ask = "Stand near your group members (in view). Stay still.",
		skip = function()
			return not IsInGroup() and "not in a group: join one and run again to check group names" or nil
		end,
		ready = function() return true end,
		checks = function()
			Say("  " .. SettingLine())
			local wants = ns.plates and ns.plates.friendWants
			Say(("  group rows wanted %s"):format(tostring(wants and wants.groupRows)))
			Check("setting on in a group (Group members rows)", not (wants and wants.groupRows) or SetHeld(),
				SettingLine())
			local seen = 0
			for _, unit in ipairs(GroupUnits()) do
				if Ask(UnitExists, unit) and not Ask(UnitIsUnit, unit, "player") then
					local plate = C_NamePlate.GetNamePlateForUnit and Ask(C_NamePlate.GetNamePlateForUnit, unit)
					local name = tostring(Ask(UnitName, unit))
					if plate then
						seen = seen + 1
						local shown, detail = NameShowing(unit, plate)
						Check(("%s's name shows on their plate"):format(name), shown, detail)
					else
						Say(("  %s: no plate (out of range or view: %s)"):format(name,
							Ask(UnitIsVisible, unit) and "visible" or "not visible"))
					end
				end
			end
			if seen == 0 then Say("  no group member near enough for a plate: stand closer and run again") end
		end },
}

local function Finish(done)
	if run.ticker then run.ticker:Cancel() end
	meter:Hide()
	m = nil
	Turn(false)
	Say(("done: %d PASS, %d FAIL%s"):format(run.pass, run.fail, done and "" or " (stopped early)"))
	run = nil
	ns.PadTestBox(done and "Test done. /reload, then say \"check log\"." or "Test stopped.", "", 1, 0.82, 0)
	C_Timer.After(12, function() if not run then ns.PadTestBoxHide() end end)
end

local function Box(text, sub, waiting)
	ns.PadTestBox(text, sub, waiting and 1 or 0.3, waiting and 0.82 or 1, waiting and 0 or 0.3)
end

-- Phases of a step: "wait" (for what it asks), "settle", "turn" (or "check"
-- for a still step), then the next step.
local function Tick()
	local now = GetTime() - run.at
	if InCombatLockdown() then
		Say("stopped: a fight started")
		Finish(false)
		return
	end
	if now < SETUP then
		Box("Stand in a BUSY city spot (lots of players), out of a fight, CineMode ON. Follow the box: it asks you to "
			.. "target or clear, then says HANDS OFF while it turns the camera.", ("Starts in %d"):format(math.ceil(SETUP - now)),
			true)
		return
	end
	if run.index == 0 then
		run.index, run.phase, run.phaseAt = 1, "wait", GetTime()
		if not ns.lastCinematic then Say("note: CineMode was off at the start; the checks expect it on") end
	end
	local step = STEPS[run.index]
	if not step then
		Finish(true)
		return
	end
	local into = GetTime() - run.phaseAt
	local function Next()
		run.index, run.phase, run.phaseAt = run.index + 1, "wait", GetTime()
	end
	if run.phase == "wait" then
		if not run.said then
			run.said = true
			Say(("--- step %d: %s (CineMode %s, plates up %d) ---"):format(run.index, step.key, tostring(ns.lastCinematic),
				#Plates()))
			local skipped = step.skip and step.skip()
			if skipped then
				Say("  skipped: " .. skipped)
				run.said = nil
				Next()
				return
			end
		end
		if step.ready() then
			run.phase, run.phaseAt, run.said = "settle", GetTime(), nil
		elseif into > WAIT_MAX then
			Say(("  skipped: waited %d sec for: %s"):format(WAIT_MAX, step.ask))
			run.said = nil
			Next()
		else
			Box(("%d/%d: %s"):format(run.index, #STEPS, step.ask), ("WAITING FOR YOU: %d sec"):format(
				math.ceil(WAIT_MAX - into)), true)
		end
		return
	end
	if run.phase == "settle" then
		if not step.ready() then
			Say("  undone before it settled: waiting again")
			run.phase, run.phaseAt = "wait", GetTime()
			run.said = true
			return
		end
		if into >= SETTLE then
			local ok, err = pcall(step.checks)
			if not ok then Say("  error in checks: " .. tostring(err)) end
			if step.turn then
				Turn(true)
				Measure()
				run.phase, run.phaseAt, run.shot = "turn", GetTime(), nil
			else
				Say("  " .. Shot(("step %d %s"):format(run.index, step.key)))
				Next()
			end
		else
			Box(("%d/%d: %s"):format(run.index, #STEPS, step.ask), "HANDS OFF: checking", false)
		end
		return
	end
	if run.phase == "turn" then
		if not run.shot and into >= TURN_SECONDS / 2 then
			run.shot = true
			Say("  " .. Shot(("step %d %s"):format(run.index, step.key)))
			return
		end
		if into >= TURN_SECONDS then
			Turn(false)
			local line, figures = Result()
			Say("  " .. line)
			if step.after then
				local ok, err = pcall(step.after, figures)
				if not ok then Say("  error in after-checks: " .. tostring(err)) end
			end
			Next()
			return
		end
		Box(("%d/%d: HANDS OFF, turning the camera"):format(run.index, #STEPS), ("RECORDING: %d sec left"):format(
			math.ceil(TURN_SECONDS - into)), false)
	end
end

function ns.FriendPlatesTest()
	if run then
		Finish(false)
		return
	end
	if InCombatLockdown() then
		ns.Print("friend plates test: not in a fight")
		return
	end
	CinematicDB.friendPlatesLog = {}
	run = { at = GetTime(), index = 0, notes = {}, pass = 0, fail = 0 }
	Say(("start: %s (game %s), CineMode %s, in group %s, plates up %d; %s"):format(ns.isRetail and "retail" or "classic",
		tostring((select(4, GetBuildInfo()))), tostring(ns.lastCinematic), tostring(IsInGroup()), #Plates(),
		SettingLine()))
	local wants = ns.plates and ns.plates.friendWants
	if wants then
		Say(("rows: Friends rows %s, Group members rows %s, Your target names %s, Your target plates %s"):format(
			tostring(wants.players), tostring(wants.groupRows), tostring(wants.targetNames), tostring(wants.target)))
	end
	run.ticker = C_Timer.NewTicker(0.25, function()
		local ok, err = pcall(Tick)
		if not ok then
			Say("error: " .. tostring(err))
			if run then Finish(false) end
		end
	end)
	ns.Print("friend plates test: follow the box (type it again to stop)")
end
