-- /cine debug peekdebuffs: one run proving a buff peek leaves the debuffs
-- faded and a debuff peek still brings them up (a player's rested XP debuff,
-- moved to the middle of the screen, came up with every kill's buff).
-- Runs itself in CineMode: waits for the buffs to fade, starts a buff peek
-- (ns.StartBuffPeek), then once all is faded again a debuff peek
-- (ns.StartDebuffPeek), logging BuffFrame's and DebuffFrame's fade levels as
-- they change, with a screenshot in each peek. Log: CinematicDB.peekDebuffLog.
-- Dev copy only (CinematicDev.toc).
local ADDON_NAME, ns = ...

local run -- { at, phase, phaseAt, ticker, kept, max = { [phase] = { buff, debuff } }, last }

local function Log(text)
	local log = ns.db.peekDebuffLog
	if #log < 2000 then
		log[#log + 1] = ("%.1fs %s"):format(GetTime() - run.at, text)
	end
end

local function AlphaOf(name)
	for _, entry in ipairs(ns.managed or {}) do
		if entry.name == name then return type(entry.alpha) == "number" and entry.alpha or 0, true end
	end
	return 0, false
end

-- (Wrapped: C_Timer refused the game's Screenshot itself on WoW Forever.)
local function Shot() Screenshot() end

local PHASES = {
	{ key = "settle", say = "Waiting for the buffs and debuffs to fade", sub = "keep the mouse off them" },
	{ key = "buff", say = "BUFF PEEK: only your buffs should come up", sub = "keep the mouse off them", length = 5,
		start = function() ns.StartBuffPeek(4, {}) end },
	{ key = "settle2", say = "Waiting for them to fade again", sub = "keep the mouse off them" },
	{ key = "debuff", say = "DEBUFF PEEK: your debuffs should come up", sub = "keep the mouse off them", length = 5,
		start = function() ns.StartDebuffPeek(4) end },
}

local Finish

local function Verdict()
	local buff, debuff = run.max.buff or {}, run.max.debuff or {}
	if not run.managedDebuffs then
		return "CAN'T TELL: DebuffFrame isn't one of the faded frames on this client"
	end
	local parts = {
		("buff peek: buffs up to %.2f, debuffs up to %.2f"):format(buff[1] or 0, buff[2] or 0),
		("debuff peek: debuffs up to %.2f"):format(debuff[2] or 0),
	}
	local ok = (buff[1] or 0) > 0.5 and (buff[2] or 0) < 0.05 and (debuff[2] or 0) > 0.5
	return (ok and "PASS " or "FAIL ") .. table.concat(parts, ", ")
end

local function Tick()
	local now = GetTime()
	if not ns.lastCinematic then
		ns.PadTestBox("Turn CineMode ON first", "(the test waits for it)", 1, 0.3, 0.3)
		run.phaseAt = now
		return
	end
	local phase = PHASES[run.phase]
	local buffAlpha = AlphaOf("BuffFrame")
	local debuffAlpha, managed = AlphaOf("DebuffFrame")
	run.managedDebuffs = run.managedDebuffs or managed
	local line = ("BuffFrame %.2f, DebuffFrame %.2f%s, debuff icons %s, combat %s"):format(buffAlpha, debuffAlpha,
		managed and "" or " (not managed)", tostring(ns.DebuffIconCount and ns.DebuffIconCount()), tostring(InCombatLockdown()))
	if line ~= run.last then
		run.last = line
		Log(line)
	end
	local into = now - run.phaseAt
	if phase.length then
		local max = run.max[phase.key]
		max[1], max[2] = math.max(max[1], buffAlpha), math.max(max[2], debuffAlpha)
		if not run.shot and into > 2 then
			run.shot = true
			Shot()
			Log("screenshot: " .. phase.key .. " peek")
		end
		ns.PadTestBox(phase.say, ("RECORDING: %d sec left"):format(math.max(0, math.ceil(phase.length - into))), 0.3, 1, 0.3)
		if into < phase.length then return end
	else
		ns.PadTestBox(phase.say, phase.sub, 1, 0.82, 0)
		-- (Faded, or 15 sec at most.)
		if not (into > 15 or (into > 1 and buffAlpha < 0.02 and debuffAlpha < 0.02)) then return end
	end
	run.phase, run.phaseAt, run.shot = run.phase + 1, now, nil
	local nextPhase = PHASES[run.phase]
	if not nextPhase then return Finish(true) end
	Log("phase " .. nextPhase.key)
	if nextPhase.length then
		run.max[nextPhase.key] = { 0, 0 }
		nextPhase.start()
	end
end

Finish = function(done)
	run.ticker:Cancel()
	local verdict = Verdict()
	Log("verdict " .. verdict)
	for key, value in pairs(run.kept) do ns.db[key] = value end
	run = nil
	ns.Print("peek debuffs test: " .. verdict)
	ns.Print("type /reload to save the log, then say check log")
	ns.PadTestBox(done and "Test done. Type /reload, then say check log" or "Test stopped. Type /reload", verdict, 1, 0.82, 0)
	C_Timer.After(20, function() if not run then ns.PadTestBoxHide() end end)
end

-- Typed again while running: stops.
function ns.BuffPeekDebuffTest()
	if run then
		Finish(false)
		return
	end
	ns.db.peekDebuffLog = {}
	run = { at = GetTime(), phase = 1, phaseAt = GetTime(), kept = {}, max = {} }
	for key, value in pairs({ handleFrames = true, handleBuffs = true, buffPeek = true, debuffPeek = true,
		buffPeekAfterCombat = false, debuffPeekAfterCombat = false, debuffPeekUntilGone = false }) do
		run.kept[key] = ns.db[key]
		ns.db[key] = value
	end
	local okVersion, version = pcall(C_AddOns.GetAddOnMetadata, ADDON_NAME, "Version")
	Log(("start: version %s, build %s, %s, just new %s, buffs row In combat/Always ticks as set"):format(
		okVersion and tostring(version) or "?", tostring((select(4, GetBuildInfo()))),
		ns.isRetail and "retail" or "not retail", tostring(ns.db.buffPeekOnlyNew)))
	run.ticker = C_Timer.NewTicker(0.2, function()
		local ok, err = pcall(Tick)
		if not ok then
			Log("error: " .. tostring(err))
			if run then Finish(false) end
		end
	end)
	ns.Print("peek debuffs test: follow the box (type it again to stop)")
end
