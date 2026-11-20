-- /cine debug namescale: one run to calibrate the size of names over heads
-- on WoW Forever (2026-11-20). Its plates don't scale, so ours are sized by
-- the camera's zoom plus a fixed guess at the unit's distance (PlateParts'
-- Look, UNIT_YARDS): walking up to an NPC, the game's own name grows and
-- ours may not. The run walks the same path twice, in the big test box
-- (Frames.lua's ns.PadTestBox):
--   setup   target a friendly NPC ~40 yards straight ahead, zoom set;
--   1 game  Cinematic paused (ns.Suspend): walk up to the NPC and stop;
--   back    walk back to the start spot (the box turns green there);
--   2 ours  Cinematic running again: the same walk.
-- A screenshot every SHOT_YARDS walked (from the start spot, UnitPosition;
-- every SHOT_SECONDS walking where it can't be read), so the two walks give
-- pairs at the same spots. Each shot's log line: yards walked, the target's
-- distance (exact if readable, else its interact band), the camera's zoom,
-- our Look (size, height) and the facing. Into CinematicDB.nameScaleLog.
-- Dev copy only (CinematicDev.toc).
local _, ns = ...

local SETUP, SHOT_YARDS, SHOT_SECONDS, STILL = 10, 3, 1.5, 1.5
local HOME_YARDS = 1.5 -- this near the start spot counts as back on it
local TICK = 0.1

local run -- { at, phase, phaseAt, start, shots, walked, lastShotAt, nextShot, stillSince, near, paused }

local function Say(text)
	local log = CinematicDB and CinematicDB.nameScaleLog
	if log then log[#log + 1] = ("%.1f %s"):format(run and GetTime() - run.at or 0, text) end
end

local function Call(f, ...)
	if not f then return nil end
	local ok, a, b, c, d = pcall(f, ...)
	if ok then return a, b, c, d end
	return nil
end

local function Plain(value)
	if issecretvalue and issecretvalue(value) then return nil end
	return value
end

local function Position()
	local y, x = Call(UnitPosition, "player")
	y, x = Plain(y), Plain(x)
	if type(y) == "number" and type(x) == "number" then return x, y end
	return nil
end

local function FromStart()
	local x, y = Position()
	if not (x and run.start) then return nil end
	return math.sqrt((x - run.start.x) ^ 2 + (y - run.start.y) ^ 2)
end

local function Moving()
	local speed = Plain(Call(GetUnitSpeed, "player"))
	return type(speed) == "number" and speed > 0
end

local function TargetDistance()
	local squared, checked = Call(UnitDistanceSquared, "target")
	squared, checked = Plain(squared), Plain(checked)
	if type(squared) == "number" and checked then return ("%.1fyd"):format(math.sqrt(squared)), true end
	-- (Bands: 3 = 10 yards, 2 = 11, 4 = 28.)
	for _, band in ipairs({ { 3, "<10yd" }, { 2, "<11yd" }, { 4, "<28yd" } }) do
		if Call(CheckInteractDistance, "target", band[1]) == true then return band[2], false end
	end
	return ">28yd", false
end

local function Near()
	return Call(CheckInteractDistance, "target", 3) == true
end

local function Shot(why)
	ns.PadTestBoxHide()
	local ok, err = pcall(function() Screenshot() end)
	local size, y
	if ns.PlateNameLook then size, y = Call(ns.PlateNameLook) end
	local walked = FromStart()
	run.shots[run.phase] = (run.shots[run.phase] or 0) + 1
	Say(("  shot %s #%d %s: walked %s, target %s, zoom %.1f, our size %s y %s, facing %s, %s"):format(run.phase,
		run.shots[run.phase], why, walked and ("%.1fyd"):format(walked) or "?", (TargetDistance()),
		Plain(Call(GetCameraZoom)) or -1, tostring(size), tostring(y),
		tostring(Plain(Call(GetPlayerFacing)) and ("%.2f"):format(GetPlayerFacing()) or "?"),
		ok and date("%m%d%y_%H%M%S") or ("failed: " .. tostring(err))))
end

local function Box(text, sub, r, g, b)
	ns.PadTestBox(text, sub, r or 1, g or 0.82, b or 0)
end

local function Phase(name)
	run.phase, run.phaseAt = name, GetTime()
	run.nextShot, run.lastShotAt, run.stillSince, run.near = 0, 0, nil, false
	Say(("--- %s ---"):format(name))
end

local function Finish(done)
	if run.ticker then run.ticker:Cancel() end
	if run.paused and ns.Resume then
		ns.Resume()
		Say("  Cinematic started again")
	end
	Say(("verdict: game walk %d shots, ours %d shots, position %s"):format(run.shots.game or 0, run.shots.ours or 0,
		run.start and "read" or "unreadable (shots by time)"))
	run = nil
	Box(done and "Name scale test done." or "Name scale test stopped.", "/reload, then say \"check log\"")
	C_Timer.After(15, function() if not run then ns.PadTestBoxHide() end end)
end

-- A walk: a shot at the start, every SHOT_YARDS (or SHOT_SECONDS walking),
-- one more on stopping by the NPC; done once stood still that near.
local function Walk(title)
	local name = UnitName("target") or "the NPC"
	local walked = FromStart()
	if run.nextShot == 0 then
		Shot("start")
		run.nextShot, run.lastShotAt = SHOT_YARDS, GetTime()
	elseif walked and walked >= run.nextShot then
		Shot("")
		run.nextShot = run.nextShot + SHOT_YARDS
	elseif not walked and Moving() and GetTime() - run.lastShotAt >= SHOT_SECONDS then
		Shot("")
		run.lastShotAt = GetTime()
	end
	if Near() then run.near = true end
	if run.near and not Moving() then
		run.stillSince = run.stillSince or GetTime()
		if GetTime() - run.stillSince >= STILL then
			Shot("end")
			return true
		end
	else
		run.stillSince = nil
	end
	Box(("%s: WALK slowly straight to %s and stop next to them. Don't zoom or turn the camera."):format(title, name),
		run.near and "Close enough: STOP" or "Walking...", 0.3, 1, 0.3)
	return false
end

local function Tick()
	if not run then return end
	local now = GetTime()
	if run.phase == "setup" then
		local left = SETUP - (now - run.phaseAt)
		local target = UnitExists("target") and not UnitIsPlayer("target")
		if left > 0 or not target then
			Box("Out of combat, TARGET a friendly NPC about 40 yards STRAIGHT AHEAD, open ground between you. " ..
				"Set your zoom and leave it. Stand still.",
				target and ("Starts in %d"):format(math.ceil(math.max(0, left))) or "Target an NPC to start")
			return
		end
		local x, y = Position()
		run.start = x and { x = x, y = y } or nil
		Say(("start: target %s, %s, position %s, zoom %.1f, Name Style %s, close %s/%s far %s/%s"):format(
			tostring(UnitName("target")), (TargetDistance()), run.start and ("%.1f,%.1f"):format(x, y) or "unreadable",
			Plain(Call(GetCameraZoom)) or -1, tostring(ns.db and ns.db.plateNameStyle),
			tostring(ns.db and ns.db.plateNameCloseSize), tostring(ns.db and ns.db.plateNameCloseY),
			tostring(ns.db and ns.db.plateNameFarSize), tostring(ns.db and ns.db.plateNameFarY)))
		if ns.Suspend and not ns.IsSuspended() then
			ns.Suspend("name scale test, walk 1")
			run.paused = true
		end
		Phase("game")
	elseif run.phase == "game" then
		if Walk("1/2 GAME'S NAMES (Cinematic paused)") then Phase("back") end
	elseif run.phase == "back" then
		local away = FromStart()
		local home
		if away then
			home = away <= HOME_YARDS
		else
			home = not Near() and Call(CheckInteractDistance, "target", 4) ~= true
		end
		if home and not Moving() then
			run.stillSince = run.stillSince or now
			if now - run.stillSince >= STILL then
				if run.paused and ns.Resume then
					ns.Resume()
					run.paused = false
				end
				Phase("ours")
				return
			end
			Box("Back on the start spot. FACE the NPC as before and stand still.", "Starting walk 2...", 0.3, 1, 0.3)
		else
			run.stillSince = nil
			Box("Walk BACK to where you started, then face the NPC again (keep it targeted, same zoom).",
				away and ("%.1f yards from the start spot"):format(away) or "Past 28 yards from the NPC")
		end
	elseif run.phase == "ours" then
		if Walk("2/2 CINEMATIC'S NAMES") then Finish(true) end
	end
end

-- Typed again while running: stops.
function ns.NameScaleTest()
	if run then
		Finish(false)
		return
	end
	if InCombatLockdown() then
		ns.Print("name scale test: out of combat please.")
		return
	end
	CinematicDB.nameScaleLog = {}
	run = { at = GetTime(), shots = {} }
	Phase("setup")
	Say(("start: %s (game %s), Cinematic %s"):format(ns.isRetail and "retail" or "not retail",
		tostring((select(4, GetBuildInfo()))),
		tostring(C_AddOns and C_AddOns.GetAddOnMetadata and Call(C_AddOns.GetAddOnMetadata, "Cinematic", "Version"))))
	run.ticker = C_Timer.NewTicker(TICK, function()
		local ok, err = pcall(Tick)
		if not ok then
			Say("error: " .. tostring(err))
			if run then Finish(false) end
		end
	end)
	ns.Print("name scale test: follow the box (type it again to stop)")
end
