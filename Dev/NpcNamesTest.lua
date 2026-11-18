-- /cine debug npcnames: one run on guards' names flashing up as you turn
-- (2026-11-18, Stormwind: a Stormwind City Patroller's name up one moment,
-- gone the next; no title, so the Service NPCs row shouldn't keep it). In a
-- city among guards, CineMode on, no target; steps in the big test box
-- (Frames.lua's ns.PadTestBox):
--   1 still   hands off, the camera doesn't move: the baseline
--   2 turn    hands off, the camera turns left by itself
--   3 turn    the same, turning right
-- Every frame, each NPC plate (not players): whether its name shows, as
-- Effects works it out (/cine debug names' line: its alphas) and as drawn
-- (the plate's and our name text's alpha). Each time a name with no Service
-- NPCs match comes up (a flash), the log gets the unit, how long the plate
-- had been up, soft target / mouseover / target, the full reason line, and
-- how long it stayed; the game's UnitName* settings at the start and each
-- time one changes; a screenshot every 3 sec while turning. A verdict per
-- step: PASS with no flash, else FAIL with the units and reasons. Into
-- CinematicDB.npcNamesLog. Dev copy only (CinematicDev.toc).
-- Also the other way round (2026-11-18, vendors' names at a camp gone for a
-- split second as you turn fast): a name that was drawn and isn't any more
-- while its plate stays (a DROP: logged with what's drawn, the reason line,
-- asleep / waiting to wake, Service NPCs match, how many frames it lasted),
-- a plate that comes and takes frames to draw its name (LATE: the same), and
-- each drawn name's plate going and coming back (its unit out of view and
-- back: how long it was gone). One-frame drops may be this sampler running
-- before Cinematic draws that frame: the frame count says.
local _, ns = ...

local SETUP, STEP, SHOT_EVERY = 8, 12, 3 -- seconds
local FAST = 2 -- of the camera's yaw speed (as FriendPlatesTest's)
local NAME_CVARS = { "UnitNameNPC", "UnitNameFriendlySpecialNPCName", "UnitNameInteractiveNPC",
	"UnitNameNonCombatCreatureName", "UnitNameHostleNPC", "UnitNameForceHideMinus", "nameplateShowFriendlyNPCs",
	"nameplateShowAll", "nameplateShowOnlyNames", "SoftTargetInteract", "SoftTargetFriend" }
local STEPS = {
	{ key = "still", say = "HANDS OFF, don't move: the camera stays still" },
	{ key = "turn left", turn = "left", say = "HANDS OFF: the camera turns LEFT by itself" },
	{ key = "turn right", turn = "right", say = "HANDS OFF: the camera turns RIGHT by itself" },
	{ key = "fast left", turn = "left", speed = FAST * 2, say = "HANDS OFF: the camera turns LEFT, FAST" },
	{ key = "fast right", turn = "right", speed = FAST * 2, say = "HANDS OFF: the camera turns RIGHT, FAST" },
}

local run -- { at, index, stepAt, shotAt, cvars, open, flashes, pass, fail }

local function Say(text)
	local log = CinematicDB and CinematicDB.npcNamesLog
	if log then log[#log + 1] = ("%.2f %s"):format(run and GetTime() - run.at or 0, text) end
end
local function Plain(value)
	if issecretvalue and issecretvalue(value) then return nil end
	return value
end
local function Ask(fn, ...)
	local ok, value = pcall(fn, ...)
	return ok and Plain(value) or nil
end

local turning
local function Turn(way, speed)
	if turning then
		pcall(turning == "left" and MoveViewLeftStop or MoveViewRightStop)
		turning = nil
		CinematicDB.npcNamesTurning = nil
	end
	if way then
		turning = way
		CinematicDB.npcNamesTurning = true
		pcall(way == "left" and MoveViewLeftStart or MoveViewRightStart, speed or FAST)
	end
end
-- (Cut short by a /reload: the turning stops.)
local restorer = CreateFrame("Frame")
restorer:RegisterEvent("PLAYER_ENTERING_WORLD")
restorer:SetScript("OnEvent", function(self)
	self:UnregisterAllEvents()
	if CinematicDB and CinematicDB.npcNamesTurning then
		pcall(MoveViewLeftStop)
		pcall(MoveViewRightStop)
		CinematicDB.npcNamesTurning = nil
	end
end)

-- When each plate got its unit (its age at a flash).
local addedAt = {}
local events = CreateFrame("Frame")
events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
events:SetScript("OnEvent", function(_, event, unit)
	local plate = C_NamePlate.GetNamePlateForUnit and Ask(C_NamePlate.GetNamePlateForUnit, unit)
	if plate then addedAt[plate] = event == "NAME_PLATE_UNIT_ADDED" and GetTime() or nil end
	if not (run and run.open and plate) then return end
	local now = GetTime()
	local guid = Ask(UnitGUID, unit)
	local who = ("%s [%s]"):format(tostring(Ask(UnitName, unit)), unit)
	if event == "NAME_PLATE_UNIT_REMOVED" then
		if run.open[plate] then
			local flash = run.open[plate]
			Say(("  flash over (plate removed): %s, up %.2f s"):format(flash.who, now - flash.at))
			run.open[plate] = nil
		end
		local drop = run.drop[plate]
		if drop then
			Say(("  drop over (plate removed): %s, blank %.3f s, %d frames"):format(drop.who, now - drop.at,
				drop.frames))
			run.drop[plate] = nil
		end
		if run.shown[plate] then
			if run.step then run.step.gone = run.step.gone + 1 end
			-- (Kept for its return by PlateParts? Its handler may run after this one.)
			local near = ns.plateSightNear
			local okSight, sightLine = pcall(ns.DescribePlateSight, plate)
			Say(("    as it went: kept for return %s; %s"):format(
				tostring(guid and near and near.left and near.left[guid] and true or false),
				okSight and tostring(sightLine) or "sight unreadable"))
			if guid then run.goneAt[guid] = now end
			Say(("  plate gone: %s (name was drawn), plate up %s s"):format(who,
				addedAt[plate] and ("%.2f"):format(now - addedAt[plate]) or "?"))
		end
		run.shown[plate], run.late[plate] = nil, nil
	else
		run.shown[plate], run.drop[plate] = nil, nil
		run.late[plate] = { who = who, at = now, frames = 0 }
		local goneAt = guid and run.goneAt[guid]
		if goneAt then
			run.goneAt[guid] = nil
			-- (Whether PlateParts skipped the sight wait for it: plateSightNear.back.)
			local near = ns.plateSightNear
			Say(("  plate back: %s after %.2f s gone; sight wait skipped %s"):format(who, now - goneAt,
				tostring(near and near.back and near.back[plate] or false)))
		end
	end
end)

local function CVarLine()
	local parts = {}
	for _, cvar in ipairs(NAME_CVARS) do parts[#parts + 1] = cvar .. "=" .. tostring(GetCVar(cvar)) end
	return table.concat(parts, " ")
end

local function Alpha(region)
	if not region then return nil end
	local ok, alpha = pcall(region.GetEffectiveAlpha or region.GetAlpha, region)
	return ok and Plain(alpha) or nil
end

-- One plate now: nil for players and plates without a unit; else whether
-- its name shows (worked out, drawn), whether Service NPCs matches it, its
-- reason line and what's drawn.
local function Look(plate)
	local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
	if not unit then return nil end
	local guid = Ask(UnitGUID, unit)
	if type(guid) == "string" and guid:find("^Player%-") then return nil end
	local okLine, line = pcall(ns.DescribePlateNameKept, unit, plate)
	line = okLine and type(line) == "string" and line or ("unreadable: " .. tostring(line))
	local alpha, _, name = line:match("alphas=([%d%.%-]+)/([%d%.%-]+)/([%d%.%-]+)")
	alpha, name = tonumber(alpha) or 0, tonumber(name) or 0
	local asleep = ns.PlateAsleep and ns.PlateAsleep(plate) or false
	local waking = ns.plateSleep and ns.plateSleep.pending[plate] and true or false
	local worked = alpha > 0.05 and name > 0.05 and not asleep
	-- (As drawn: our name text where we draw it, else the game's.)
	local ours = ns.PlateNameText and ns.PlateNameText(plate)
	local text = ours or (plate.UnitFrame and plate.UnitFrame.name)
	local textShown = text and Ask(text.IsVisible, text) or false
	-- (And the second line: a vendor's title shows there with its name faded,
	-- Service NPCs' Titles only. PlateGuild.lua.)
	local line2 = ns.PlateLine2Text and ns.PlateLine2Text(plate)
	local line2Shown = line2 and Ask(line2.IsVisible, line2) or false
	local plateShown = Ask(plate.IsVisible, plate)
	local drawn = plateShown and ((textShown and (Alpha(text) or 0) > 0.05)
		or (line2Shown and (Alpha(line2) or 0) > 0.05)) or false
	local okMatch, match = pcall(ns.PlateServiceMatch, plate, unit)
	local okSight, sightLine = pcall(ns.DescribePlateSight, plate)
	sightLine = okSight and tostring(sightLine) or "sight unreadable"
	return {
		unit = unit, worked = worked, drawn = drawn and true or false, match = okMatch and match and true or false,
		who = ("%s [%s]"):format(tostring(Ask(UnitName, unit)), unit), line = line,
		drawnLine = ("drawn: plate alpha %s visible %s, %s text visible %s alpha %s, line 2 %s alpha %s, asleep %s"
			.. ", waiting to wake %s, Service NPCs match %s"):format(
			tostring(Alpha(plate)), tostring(plateShown), ours and "our" or "game",
			tostring(textShown), tostring(Alpha(text)), line2 and ("visible " .. tostring(line2Shown)) or "none",
			tostring(line2 and Alpha(line2)), tostring(asleep), tostring(waking),
			tostring(okMatch and match and true or false)) .. "; " .. sightLine,
		tags = ("soft interact %s, soft friend %s, mouseover %s, target %s"):format(
			tostring(Ask(UnitIsUnit, unit, "softinteract")), tostring(Ask(UnitIsUnit, unit, "softfriend")),
			tostring(Ask(UnitIsUnit, unit, "mouseover")), tostring(Ask(UnitIsUnit, unit, "target"))),
	}
end

-- Per frame while a step runs.
local sampler = CreateFrame("Frame")
sampler:Hide()
ns.SetOnUpdate(sampler, function()
	if not (run and run.open) then return end
	local now = GetTime()
	local cvars = CVarLine()
	if cvars ~= run.cvars then
		Say("  name settings changed: " .. cvars)
		run.cvars = cvars
	end
	local step = run.step
	if not step then return end
	local drawnNow, npcs = 0, 0
	for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
		local look = Look(plate)
		if look then
			npcs = npcs + 1
			if look.drawn then drawnNow = drawnNow + 1 end
		end
		local bad = look and not look.match and (look.worked or look.drawn)
		local open = run.open[plate]
		if bad and not open then
			step.flashes = step.flashes + 1
			step.who[look.who] = (step.who[look.who] or 0) + 1
			run.open[plate] = { who = look.who, at = now }
			local age = addedAt[plate] and ("%.2f"):format(now - addedAt[plate]) or "?"
			Say(("  FLASH %s: worked out %s, drawn %s, plate up %s s; %s"):format(look.who, tostring(look.worked),
				tostring(look.drawn), age, look.tags))
			Say("    " .. look.drawnLine)
			Say("    " .. look.line)
			if not step.shot then
				step.shot = true
				ns.PadTestBoxHide()
				pcall(function() Screenshot() end)
				Say(("    screenshot (first flash) at %s"):format(date("%m%d%y_%H%M%S")))
			end
		elseif open and not bad then
			Say(("  flash over: %s, up %.2f s%s"):format(open.who, now - open.at,
				look and look.match and " (now matched Service NPCs)" or ""))
			run.open[plate] = nil
		end
		-- (The other way: a name drawn that goes, its plate staying.)
		if look then
			local drop, late = run.drop[plate], run.late[plate]
			if look.drawn then
				if drop then
					Say(("  drop over: %s, blank %.3f s, %d frames"):format(drop.who, now - drop.at, drop.frames))
					run.drop[plate] = nil
				end
				if late then
					if late.frames > 0 then
						step.late = step.late + 1
						step.lateWho[look.who] = (step.lateWho[look.who] or 0) + 1
						Say(("  LATE %s: plate came, name blank %.3f s, %d frames; first blank frame:"):format(
							look.who, now - late.at, late.frames))
						Say("    " .. late.drawnLine)
						Say("    " .. late.line)
					end
					run.late[plate] = nil
				end
				run.shown[plate] = true
			elseif drop then
				drop.frames = drop.frames + 1
			elseif run.shown[plate] then
				step.drops = step.drops + 1
				step.dropWho[look.who] = (step.dropWho[look.who] or 0) + 1
				run.drop[plate] = { who = look.who, at = now, frames = 1 }
				Say(("  DROP %s: name was drawn, now not; worked out %s, plate up %s s; %s"):format(look.who,
					tostring(look.worked), addedAt[plate] and ("%.2f"):format(now - addedAt[plate]) or "?", look.tags))
				Say("    " .. look.drawnLine)
				Say("    " .. look.line)
			elseif late and now - late.at > 1 then
				if look.match then
					-- (A Service NPCs name still not drawn a second after its plate came.)
					Say(("  NEVER DRAWN %s: matched Service NPCs, plate up 1 s, name blank"):format(look.who))
					Say("    " .. look.drawnLine)
					Say("    " .. look.line)
					step.late = step.late + 1
					step.lateWho[look.who] = (step.lateWho[look.who] or 0) + 1
				end
				run.late[plate] = nil -- (a name not meant to show: not late)
			elseif late then
				late.frames = late.frames + 1
				if late.frames == 1 then late.drawnLine, late.line = look.drawnLine, look.line end
			end
		end
	end
	step.frames = step.frames + 1
	step.drawnSum = step.drawnSum + drawnNow
	step.npcSum = step.npcSum + npcs
	step.drawnMax = math.max(step.drawnMax, drawnNow)
	step.drawnMin = math.min(step.drawnMin, drawnNow)
	if drawnNow == 0 and npcs > 0 then step.noneFrames = step.noneFrames + 1 end
end)

-- Every NPC plate as it is now, one line each (at each step's start and end).
local function Dump(label)
	local n = 0
	for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
		local look = Look(plate)
		if look then
			n = n + 1
			Say(("  %s %s: drawn %s, worked out %s; %s"):format(label, look.who, tostring(look.drawn),
				tostring(look.worked), look.drawnLine))
			Say("      " .. look.line)
		end
	end
	if n == 0 then Say(("  %s: no NPC plates up"):format(label)) end
end

local function Box(text, sub, waiting)
	ns.PadTestBox(text, sub, waiting and 1 or 0.3, waiting and 0.82 or 1, waiting and 0 or 0.3)
end

local function EndStep()
	local step = run.step
	if not step then return end
	Turn(nil)
	Dump("at end")
	local frames = math.max(step.frames, 1)
	Say(("  names drawn per frame: avg %.1f of %.1f NPC plates, min %d, max %d; %d of %d frames with NPC plates up"
		.. " but no name drawn"):format(step.drawnSum / frames, step.npcSum / frames,
		step.frames > 0 and step.drawnMin or 0, step.drawnMax, step.noneFrames, step.frames))
	for plate, open in pairs(run.open) do
		Say(("  flash still up at the step's end: %s, %.2f s"):format(open.who, GetTime() - open.at))
		run.open[plate] = nil
	end
	for plate, drop in pairs(run.drop) do
		Say(("  drop still on at the step's end: %s, %.3f s, %d frames"):format(drop.who, GetTime() - drop.at,
			drop.frames))
		run.drop[plate] = nil
	end
	local function List(who)
		local list = {}
		for name, count in pairs(who) do list[#list + 1] = ("%s x%d"):format(name, count) end
		return table.concat(list, ", ")
	end
	if step.flashes == 0 then
		run.pass = run.pass + 1
		Say(("  PASS %s flashes: no NPC name without a Service NPCs match came up"):format(step.key))
	else
		run.fail = run.fail + 1
		Say(("  FAIL %s flashes: %d: %s"):format(step.key, step.flashes, List(step.who)))
	end
	if step.drawnMax == 0 then
		Say(("  NO DATA %s drops: no NPC name was drawn the whole step (as the recorder reads it), so none could"
			.. " drop; compare the screenshots"):format(step.key))
	elseif step.drops + step.late == 0 then
		run.pass = run.pass + 1
		Say(("  PASS %s drops: no drawn name went blank, no plate came blank (%d drawn plates went and came)")
			:format(step.key, step.gone))
	else
		run.fail = run.fail + 1
		Say(("  FAIL %s drops: %d drops (%s), %d late (%s); %d drawn plates went and came"):format(step.key,
			step.drops, List(step.dropWho), step.late, List(step.lateWho), step.gone))
	end
	run.step = nil
end

local function Finish(done)
	if run.ticker then run.ticker:Cancel() end
	EndStep()
	sampler:Hide()
	Turn(nil)
	Say(("done: %d PASS, %d FAIL%s"):format(run.pass, run.fail, done and "" or " (stopped early)"))
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
		Box("Stand CLOSE to NPCs whose names show (vendors, names up now), out of a fight, CineMode ON, NO target. "
			.. "Then HANDS OFF: the camera turns by itself.", ("Starts in %d"):format(math.ceil(SETUP - now)), true)
		return
	end
	local into = run.step and GetTime() - run.step.at or STEP
	if into >= STEP then
		EndStep()
		run.index = run.index + 1
		local spec = STEPS[run.index]
		if not spec then
			Finish(true)
			return
		end
		run.step = { key = spec.key, at = GetTime(), flashes = 0, who = {}, shotAt = GetTime(), drops = 0,
			dropWho = {}, late = 0, lateWho = {}, gone = 0, frames = 0, drawnSum = 0, npcSum = 0, drawnMax = 0,
			drawnMin = math.huge, noneFrames = 0 }
		Say(("--- step %d: %s (CineMode %s, target %s, plates up %d) ---"):format(run.index, spec.key,
			tostring(ns.lastCinematic), tostring(Ask(UnitExists, "target") or false), #(C_NamePlate.GetNamePlates() or {})))
		Dump("at start")
		Turn(spec.turn, spec.speed)
		into = 0
	end
	local spec = STEPS[run.index]
	if GetTime() - run.step.shotAt >= SHOT_EVERY then
		run.step.shotAt = GetTime()
		ns.PadTestBoxHide()
		pcall(function() Screenshot() end)
		Say(("  screenshot at %s"):format(date("%m%d%y_%H%M%S")))
		return
	end
	Box(("%d/%d: %s"):format(run.index, #STEPS, spec.say), ("RECORDING: %d sec left"):format(math.ceil(STEP - into)),
		false)
end

function ns.NpcNamesTest()
	if run then
		Finish(false)
		return
	end
	if InCombatLockdown() then
		ns.Print("npc names test: not in a fight")
		return
	end
	CinematicDB.npcNamesLog = {}
	run = { at = GetTime(), index = 0, open = {}, pass = 0, fail = 0, cvars = CVarLine(), drop = {}, late = {},
		shown = {}, goneAt = {} }
	Say(("start: %s (game %s), CineMode %s, plates up %d, Service NPCs show %s"):format(
		ns.isRetail and "retail" or "classic", tostring((select(4, GetBuildInfo()))), tostring(ns.lastCinematic),
		#(C_NamePlate.GetNamePlates() or {}), tostring(ns.db.nameServiceShow)))
	Say("name settings: " .. run.cvars)
	Say(("return fix loaded: %s"):format(tostring(ns.plateSightNear and ns.plateSightNear.back ~= nil or false)))
	sampler:Show()
	run.ticker = C_Timer.NewTicker(0.25, function()
		local ok, err = pcall(Tick)
		if not ok then
			Say("error: " .. tostring(err))
			if run then Finish(false) end
		end
	end)
	ns.Print("npc names test: follow the box (type it again to stop)")
end
