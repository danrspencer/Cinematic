-- /cine debug officon: whether the game's own offscreen icon on a plate
-- (UnitFrame.behindCameraIcon, atlas common-icon-offscreen; its IsShown is
-- readable, found by /cine debug offscreen on Forever, 2026-11-20) tells a
-- plate pinned to the screen's edge from one in view. That run saw it go on
-- for 1 plate of 3 behind you, but couldn't prove the plate kept its unit.
-- One run, out of a fight, CineMode off (it waits for that, then turns Show
-- Offscreen on for the run and puts yours back, a /reload too):
--   1 in front   3+ plates in front of you, stand still
--   2 behind     turn around once (it waits, no time limit)
--   3 back       turn back to face them again
-- Every 0.25 s, each plate's icon, unit and (where readable) name and GUID:
-- every change is logged as it happens, a plate taking a new unit too. Then
-- per unit seen in all three steps, its icon in each (off/on/off is the
-- match), and a verdict. Into CinematicDB.offIconLog. Dev copy only.
local _, ns = ...

local SETTLE = 1.5 -- seconds still before a step's readings count
local SAMPLE = 2 -- seconds of readings per step
local TURNED = 2.4 -- radians away from your first facing for step 2 (about 140 degrees)
local BACK = 0.8 -- radians from your first facing for step 3 (about 45 degrees)

local run
local function Say(text)
	local log = CinematicDB and CinematicDB.offIconLog
	if log then log[#log + 1] = ("%.2f %s"):format(run and GetTime() - run.at or 0, text) end
end
local function Secret(value) return issecretvalue and issecretvalue(value) end
local function Plain(fn, ...)
	local ok, value = pcall(fn, ...)
	if not ok then return nil, "error" end
	if Secret(value) then return nil, "secret" end
	return value
end

local function PutBack()
	local saved = CinematicDB and CinematicDB.offIconWas
	if saved == nil or InCombatLockdown() then return end
	pcall(SetCVar, "nameplateShowOffscreen", saved)
	CinematicDB.offIconWas = nil
end
local restorer = CreateFrame("Frame")
restorer:RegisterEvent("PLAYER_LOGIN")
restorer:SetScript("OnEvent", function(self)
	self:UnregisterAllEvents()
	C_Timer.After(1, PutBack)
end)

local function Plates()
	return C_NamePlate and C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlates() or {}
end
local function Facing()
	local facing = Plain(GetPlayerFacing)
	return facing
end
local function Angle(a, b)
	local diff = math.abs(a - b) % (2 * math.pi)
	return diff > math.pi and 2 * math.pi - diff or diff
end

-- One plate now: its unit, who (name or GUID when readable, else the token),
-- and its icon: "on", "off", or why it can't be read.
local function ReadPlate(plate)
	local frame = plate.UnitFrame
	local unit = plate.namePlateUnitToken or (frame and frame.unit)
	local guid = unit and Plain(UnitGUID, unit)
	local name = unit and Plain(UnitName, unit)
	local icon = frame and frame.behindCameraIcon
	local state
	if not icon then
		state = "no icon"
	else
		local shown, why = Plain(icon.IsShown, icon)
		state = why or (shown and "on" or "off")
	end
	local alpha = frame and Plain(frame.GetAlpha, frame)
	return {
		unit = tostring(unit),
		who = guid or ("?" .. tostring(unit)),
		label = ("%s (%s)"):format(name or "?", tostring(unit)),
		icon = state,
		alpha = alpha and ("%.2f"):format(alpha) or "?",
	}
end

local function Box(text, sub) ns.PadTestBox(text, sub or "", 1, 0.82, 0) end

-- Watches every plate each tick: logs changes, and while a step samples,
-- counts each unit's icon states for that step.
local function Watch()
	local seen = {}
	for _, plate in ipairs(Plates()) do
		local now = ReadPlate(plate)
		seen[plate] = true
		local was = run.plates[plate]
		if not was then
			Say(("plate up: %s icon %s alpha %s [%s]"):format(now.label, now.icon, now.alpha, run.phase))
		elseif was.who ~= now.who then
			Say(("plate took a new unit: %s -> %s, icon %s [%s]"):format(was.label, now.label, now.icon, run.phase))
		elseif was.icon ~= now.icon then
			Say(("icon %s -> %s: %s alpha %s, facing %s [%s]"):format(was.icon, now.icon, now.label, now.alpha,
				tostring(Facing() and ("%.2f"):format(Facing())), run.phase))
		end
		run.plates[plate] = now
		if run.sampling then
			local units = run.steps[run.phase]
			local entry = units[now.who] or { label = now.label, counts = {} }
			entry.counts[now.icon] = (entry.counts[now.icon] or 0) + 1
			units[now.who] = entry
		end
	end
	for plate, was in pairs(run.plates) do
		if not seen[plate] then
			Say(("plate gone: %s (icon was %s) [%s]"):format(was.label, was.icon, run.phase))
			run.plates[plate] = nil
		end
	end
end

-- A step's main state for a unit: the one it had most of the time.
local function Main(entry)
	if not entry then return "none" end
	local best, most = "none", -1
	for state, n in pairs(entry.counts) do
		if n > most then best, most = state, n end
	end
	return best
end

local function Finish(done)
	if run.ticker then run.ticker:Cancel() end
	PutBack()
	if done then
		Say("--- per unit, icon in front / behind / back again ---")
		local match, stayedOff, wrongFront, other, units = 0, 0, 0, 0, 0
		for who, entry in pairs(run.steps.front) do
			local front, behind, again = Main(entry), Main(run.steps.behind[who]), Main(run.steps.again[who])
			units = units + 1
			local kind
			if front == "off" and behind == "on" and again == "off" then
				match, kind = match + 1, "MATCH"
			elseif front == "on" or again == "on" then
				wrongFront, kind = wrongFront + 1, "on while in view"
			elseif front == "off" and behind == "off" and again == "off" then
				stayedOff, kind = stayedOff + 1, "never on"
			else
				other, kind = other + 1, "other"
			end
			Say(("  %s: %s / %s / %s  %s"):format(entry.label, front, behind, again, kind))
		end
		local verdict
		if units == 0 then
			verdict = "NO DATA: no plates read in front of you"
		elseif match > 0 and wrongFront == 0 then
			verdict = ("PASS: the icon came on behind you and went off in front for %d of %d units"):format(match, units)
		elseif wrongFront > 0 then
			verdict = ("FAIL: the icon was on for %d units in view"):format(wrongFront)
		else
			verdict = ("FAIL: the icon never followed the turn (%d never on, %d other)"):format(stayedOff, other)
		end
		Say(("%d units: %d match, %d never on, %d on in view, %d other"):format(units, match, stayedOff, wrongFront, other))
		Say("verdict: " .. verdict)
		ns.Print("officon: " .. verdict)
	end
	Say(done and "done" or "stopped early")
	run = nil
	ns.PadTestBox(done and "Test done. /reload, then say \"check log\"." or "Test stopped.", "", 1, 0.82, 0)
	C_Timer.After(12, function() if not run then ns.PadTestBoxHide() end end)
end

-- A step: wait until ready() says so (asking with prompt), settle, sample,
-- then go on to the next.
local STEPS = {
	front = { n = 1, next = "behind", prompt = "1/3: Stand where 3 or more mobs or players with plates are IN FRONT of you, close by. Stay still.",
		ready = function() return #Plates() >= 3 end },
	behind = { n = 2, next = "again", prompt = "2/3: TURN AROUND once so those plates are BEHIND you. Then stay still.",
		ready = function()
			local now = Facing()
			return now and run.facing and Angle(now, run.facing) >= TURNED or not (now and run.facing) and GetTime() - run.phaseAt >= 8
		end },
	again = { n = 3, next = nil, prompt = "3/3: TURN BACK to face them again. Then stay still.",
		ready = function()
			local now = Facing()
			return now and run.facing and Angle(now, run.facing) <= BACK or not (now and run.facing) and GetTime() - run.phaseAt >= 8
		end },
}

local function Tick()
	if InCombatLockdown() then
		Box("Leave the fight first.", "WAITING FOR YOU")
		return
	end
	if run.phase == "cine" then
		-- (CineMode holds Show Offscreen itself: off first, then ours for the run.)
		if ns.lastCinematic then
			Box("Turn CineMode OFF for this test.", "WAITING FOR YOU")
			return
		end
		CinematicDB.offIconWas = GetCVar("nameplateShowOffscreen")
		pcall(SetCVar, "nameplateShowOffscreen", "1")
		Say(("Show Offscreen was %s, now %s"):format(tostring(CinematicDB.offIconWas),
			tostring(GetCVar("nameplateShowOffscreen"))))
		run.phase, run.phaseAt, run.readyAt = "front", GetTime(), nil
		return
	end
	Watch()
	local step = STEPS[run.phase]
	if not run.readyAt then
		if not step.ready() then
			Box(step.prompt, "WAITING FOR YOU")
			return
		end
		run.readyAt = GetTime()
		if run.phase == "front" then run.facing = Facing() end
		Say(("--- step %d (%s): ready, facing %s, %d plates ---"):format(step.n, run.phase,
			tostring(Facing() and ("%.2f"):format(Facing())), #Plates()))
	end
	local into = GetTime() - run.readyAt
	run.sampling = into >= SETTLE
	if into < SETTLE + SAMPLE then
		Box(("%d/3: HANDS OFF: reading plates."):format(step.n))
		return
	end
	run.sampling = false
	pcall(Screenshot)
	if not step.next then
		Finish(true)
		return
	end
	run.phase, run.phaseAt, run.readyAt = step.next, GetTime(), nil
end

function ns.OffscreenIconTest()
	if run then
		Finish(false)
		return
	end
	if InCombatLockdown() then
		ns.Print("officon: not in a fight")
		return
	end
	CinematicDB.offIconLog = {}
	run = { at = GetTime(), phase = "cine", phaseAt = GetTime(), plates = {},
		steps = { front = {}, behind = {}, again = {} } }
	local zoom = Plain(GetCameraZoom)
	Say(("start: %s (game %s), Cinematic %s, CineMode %s, camera zoom %s"):format(ns.isRetail and "retail" or "classic",
		tostring((select(4, GetBuildInfo()))), ns.Version and ns.Version() or "?", tostring(ns.lastCinematic),
		zoom and ("%.1f"):format(zoom) or "?"))
	run.ticker = C_Timer.NewTicker(0.25, function()
		local ok, err = pcall(Tick)
		if not ok then
			Say("error: " .. tostring(err))
			if run then Finish(false) end
		end
	end)
	ns.Print("officon: follow the box (type it again to stop)")
end
