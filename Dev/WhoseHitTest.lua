-- /cine debug whosehit: one recorder run at training dummies (retail first)
-- to learn whether anything tells your hits from strangers' with no combat
-- log lines (retail sent none, 2026-11-19). The /cine debug combattext
-- recorder (Diagnostics.lua) logs every plate hit, log line and cast; this
-- adds the game's damage meter events (they fired on every hit on Forever,
-- and the meter counts only you and your group) and three timed steps:
--   1 QUIET  don't attack, near dummies others are hitting: what strangers' hits bring
--   2 ALONE  hit a dummy no one else is hitting: what your hits bring
--   3 BUSY   hit the dummies others are hitting: both at once
-- Each step's start and end are in the log (CinematicDB.combatTextLog), and
-- since the retail fix each step gives its own verdict (on screen at the end):
-- QUIET none drawn; ALONE and BUSY yours drawn.
local _, ns = ...

local STEP = 25 -- seconds per step
local LINES = 25000 -- the recorder's cap (4000 filled in 26 s at busy dummies, 2026-11-19)
local METER_EVENTS = { "DAMAGE_METER_COMBAT_SESSION_UPDATED", "DAMAGE_METER_CURRENT_SESSION_UPDATED",
	"DAMAGE_METER_RESET" }
local STEPS = {
	{ "QUIET", "Step 1 of 3: DON'T attack. Stand near dummies other players are hitting." },
	{ "ALONE", "Step 2 of 3: attack a dummy NO ONE else is hitting." },
	{ "BUSY", "Step 3 of 3: attack the dummies other players are hitting." },
}

local running
local count -- this step's: hits on plates, numbers drawn, left out idle, left out off-class
local verdicts = {}

-- What each step should show, since the retail fix (no log: the meter's
-- fighting gate and the strict school check, CombatTextStyle.lua).
local function Verdict(index, name)
	local c = count
	local line
	if c.hits == 0 then
		line = ("NO HITS ON PLATES SEEN (redo: stand by dummies others are hitting)")
	elseif name == "QUIET" then
		line = c.drawn == 0 and ("PASS: none of %d strangers' hits drawn"):format(c.hits)
			or ("FAIL: %d numbers drawn while you didn't attack (%d hits)"):format(c.drawn, c.hits)
	else
		line = c.drawn > 0 and ("PASS: %d numbers drawn; left out %d while idle, %d off-class"):format(c.drawn,
			c.idle, c.offClass)
			or ("FAIL: none of your numbers drawn (%d hits, %d left out idle, %d off-class)"):format(c.hits, c.idle,
			c.offClass)
	end
	line = ("step %d %s: %s"):format(index, name, line)
	verdicts[#verdicts + 1] = line
	return line
end

local function State(value)
	if ns.Check.Secret(value) then return "<secret>" end
	return tostring(value)
end

local function Ask(path, ...)
	local fn = ns.Check.Api(path)
	if not fn then return "none" end
	return State(fn(...))
end

local function Stop(why)
	if not running then return end
	running:UnregisterAllEvents()
	running = nil
	local rec = ns.combatTextRecord
	if rec then
		rec("WHOSEHIT stopped: " .. why)
		for _, line in ipairs(verdicts) do rec("WHOSEHIT VERDICT " .. line) end
	end
	if ns.combatTextRecord then ns.CombatTextProbe() end -- (the recorder: run again stops it)
	ns.TestPrompt(table.concat(verdicts, "\n") .. "\n\nNow /reload, then tell Claude 'check log'.", 30)
end

function ns.WhoseHitTest()
	if running then return Stop("run again") end
	if ns.IsCineModeOn and ns.IsCineModeOn() then
		ns.Print("whosehit: turn CineMode off first (it fades the plates the numbers go on).")
		return
	end
	if ns.combatTextRecord then ns.CombatTextProbe() end -- (one already running: stopped, fresh one below)
	ns.CombatTextProbe(LINES)
	local rec = ns.combatTextRecord
	if not rec then
		ns.Print("whosehit: the recorder didn't start.")
		return
	end
	-- (Counted as the recorder hears them, for each step's verdict.)
	wipe(verdicts)
	count = { hits = 0, drawn = 0, idle = 0, offClass = 0 }
	local original = rec
	rec = function(text)
		if type(text) == "string" then
			if text:find("^DRAWN ") then count.drawn = count.drawn + 1
			elseif text:find("weren't dealing damage", 1, true) then count.idle = count.idle + 1
			elseif text:find("OFF-CLASS LEFT OUT", 1, true) then count.offClass = count.offClass + 1 end
		end
		return original(text)
	end
	ns.combatTextRecord = rec
	local Check = ns.Check
	rec(("WHOSEHIT start: meter available %s, log restricted %s, log filtered events on %s, in a group %s"):format(
		Ask("C_DamageMeter.IsDamageMeterAvailable"), Ask("C_CombatLog.IsCombatLogRestricted"),
		Ask("C_CombatLog.AreFilteredEventsEnabled"), State(IsInGroup and IsInGroup())))
	running = CreateFrame("Frame")
	local events = {}
	for _, event in ipairs(METER_EVENTS) do
		events[#events + 1] = event .. "=" .. tostring(Check.RegisterEvent(running, event))
	end
	rec("WHOSEHIT meter events: " .. table.concat(events, ", "))
	-- (Hits on plates, counted for the verdicts: the recorder logs them itself.)
	Check.RegisterEvent(running, "UNIT_COMBAT")
	running:SetScript("OnEvent", function(_, event, ...)
		if event == "UNIT_COMBAT" then
			local unit = ...
			if type(unit) == "string" and not Check.Secret(unit) and unit:find("^nameplate") then
				count.hits = count.hits + 1
			end
			return
		end
		local parts = {}
		for i = 1, math.min(select("#", ...), 6) do
			local value = select(i, ...)
			parts[#parts + 1] = type(value) .. ":" .. State(value)
		end
		local log = ns.combatTextRecord
		if log then log(("METER %s (%s)"):format(event, table.concat(parts, " | "))) end
	end)
	local function Step(index)
		if not running then return end
		local log = ns.combatTextRecord
		if index > #STEPS then return Stop("all steps done") end
		local step = STEPS[index]
		if log then log(("WHOSEHIT STEP %d %s begins"):format(index, step[1])) end
		count.hits, count.drawn, count.idle, count.offClass = 0, 0, 0, 0
		ns.TestPrompt(step[2] .. (" (%d s)"):format(STEP), STEP)
		C_Timer.After(STEP, function()
			local now = ns.combatTextRecord
			if running and now then
				now(("WHOSEHIT STEP %d %s ends"):format(index, step[1]))
				now("WHOSEHIT VERDICT " .. Verdict(index, step[1]))
			end
			Step(index + 1)
		end)
	end
	ns.TestPrompt("Whose hit test: 3 steps of 25 s at training dummies. Starting in 5 s...", 5)
	C_Timer.After(5, function() Step(1) end)
end
