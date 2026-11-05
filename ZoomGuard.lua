local _, ns = ...

-- Zoom guard: a safety net for our cameras' zooms. Every zoom of ours goes
-- through ns.CameraCall / ns.CallCameraFunction (Camera.lua); this watches the
-- real camera distance each frame while one of ours is zooming. The camera
-- swinging in and out again and again (SWINGS turns of direction, each over
-- SWING_SIZE yards, inside WINDOW seconds) with you not zooming yourself is a
-- zoom gone wrong: two cameras fighting over it, or one chasing its own
-- overshoot. Then our zooms are held for a while (HOLD seconds, doubled for
-- each trip soon after another, up to HOLD_MAX); the slow zoom waits where it
-- is meanwhile (StepIdleZoom), and the trip is logged ("zoom") with who was
-- zooming. /cine debug zoom shows it too.
local SWING_SIZE = 0.75  -- yards back the other way that count as a turn of direction
local SWINGS = 3         -- turns of direction...
local WINDOW = 3         -- ...inside this many seconds trip the guard
local OURS_RECENT = 0.6  -- seconds after one of our zoom commands that the camera counts as ours
local YOURS_RECENT = 1.5 -- seconds after your own zooming that nothing counts
local HOLD = 8           -- seconds our zooms are held after a trip
local HOLD_MAX = 60
local CALM_RESET = 120   -- seconds without a trip before the hold is back to HOLD

local guard = { holdUntil = 0, hold = HOLD, trips = 0, lastTripAt = -math.huge,
	turns = {}, senders = {}, oursAt = -math.huge }
ns.zoomGuard = guard

-- Held now: our zooms are refused.
function ns.ZoomGuardHolds()
	return GetTime() < guard.holdUntil
end

local function IsZoom(name)
	return type(name) == "string" and name:find("^CameraZoom") ~= nil
end

local function NoteOurs(who, name, amount)
	local now = GetTime()
	guard.oursAt = now
	local n = tonumber(amount) or 0
	guard.frameAsk = (guard.frameAsk or 0) + (name == "CameraZoomIn" and -n or n)
	guard.frameWho = who
	guard.senders[who or "?"] = now
	guard.lastSent = ("%s %s(%.2f)"):format(tostring(who or "?"), name, tonumber(amount) or 0)
end

-- Wrapped once Camera.lua has made them (this file loads after it).
local cameraCall = ns.CameraCall
if cameraCall then
	function ns.CameraCall(who, name, ...)
		if IsZoom(name) then
			if ns.ZoomGuardHolds() then
				return false -- (refused like a claim another camera holds)
			end
			guard.sendingWho = who
		end
		local ok = cameraCall(who, name, ...)
		guard.sendingWho = nil
		if IsZoom(name) and not ok then
			-- Refused by the camera lock: who has the view, for the trace.
			local holder = ns.CameraHolder and ns.CameraHolder(who, ns.zoomWhileSteering and ns.zoomWhileSteering[who])
			guard.frameRefused = ("%s refused (%s has it)"):format(tostring(who), tostring(holder or "?"))
		end
		return ok
	end
end
local callCamera = ns.CallCameraFunction
if callCamera then
	function ns.CallCameraFunction(name, ...)
		if IsZoom(name) then
			NoteOurs(guard.sendingWho or "direct", name, ...)
		end
		return callCamera(name, ...)
	end
end

local function Trip(now, zoom)
	local who = {}
	for name, at in pairs(guard.senders) do
		if now - at < WINDOW then who[#who + 1] = name end
	end
	table.sort(who)
	if now - guard.lastTripAt > CALM_RESET then
		guard.hold = HOLD
	else
		guard.hold = math.min(HOLD_MAX, guard.hold * 2)
	end
	guard.trips = guard.trips + 1
	guard.lastTripAt = now
	guard.holdUntil = now + guard.hold
	guard.lastWho = table.concat(who, ", ")
	guard.turns = {}
	ns.Log("zoom", ("zoom guard: the camera swung in and out %d times in %d sec (now %.1f yards; zooming: %s; last %s; camera %s): our zooms held %d sec"):format(
		SWINGS, WINDOW, zoom, guard.lastWho ~= "" and guard.lastWho or "?", tostring(guard.lastSent),
		tostring(ns.activeCam or "none"), guard.hold))
end

-- The trace: the last TRACE_SECS of camera distance, frame by frame, with
-- what we asked for that frame, who, the slow zoom's phase, steering and the
-- max factor. Written to the log as a trip or a jump happens, and by
-- /cine debug zoomtrace (right after a zoom went wrong).
local TRACE_SECS = 30
local TRACE_MAX = 6000 -- frames kept at most (30 sec at 200 fps)
local JUMP_SIZE = 1     -- yards in one frame...
local JUMP_SPEED = 30   -- ...and faster than this (yards a second): a jump, not a zoom
local trace = { n = 0, head = 0, t = {}, z = {}, ask = {}, who = {}, refused = {}, ctx = {}, phase = {}, steer = {}, max = {} }
local lastJumpLog, lastSwingLog = -math.huge, -math.huge
local SWING_LOG_GAP = 30 -- seconds between logs of swings that weren't ours

local function Record(now, zoom)
	trace.head = trace.head % TRACE_MAX + 1
	local i = trace.head
	local idle = ns.GetZoomDebug and ns.GetZoomDebug()
	trace.t[i], trace.z[i] = now, zoom
	trace.ask[i], trace.who[i], trace.refused[i] = guard.frameAsk or 0, guard.frameWho, guard.frameRefused
	-- (Kept apart, not joined: this runs every frame.)
	trace.ctx[i] = idle and (idle.active or idle.restoring) and idle.context or nil
	trace.phase[i] = idle and (idle.active and idle.phase or idle.restoring and "restore") or nil
	trace.steer[i] = ns.mouseSteering and true or false
	trace.max[i] = GetCVar("cameraDistanceMaxZoomFactor")
	trace.n = math.min(trace.n + 1, TRACE_MAX)
	guard.frameAsk, guard.frameWho, guard.frameRefused = 0, nil, nil
end

-- Writes the trace to the log, a line per `step` seconds (the frame-by-frame
-- detail for the last `fine` seconds). Gives the lines written.
function ns.ZoomTraceDump(why, step, fine, secs)
	step, fine, secs = step or 0.25, fine or 0.5, math.min(secs or 10, TRACE_SECS)
	local now = GetTime()
	ns.Log("zoom", ("trace (%s): last %d sec, camera now %s, your last zoom %.1f sec ago"):format(tostring(why),
		secs, tostring(ns.activeCam or "none"), now - (ns.lastPlayerZoomAt or -math.huge)))
	local written, lastAt, ask, who, refused = 0, -math.huge, 0, {}, nil
	for k = trace.n - 1, 0, -1 do
		local i = (trace.head - k - 1) % TRACE_MAX + 1
		local t = trace.t[i]
		if t and now - t <= secs then
			ask = ask + trace.ask[i]
			if trace.who[i] then who[trace.who[i]] = true end
			refused = trace.refused[i] or refused
			if now - t <= fine or t - lastAt >= step or k == 0 then
				local names = {}
				for name in pairs(who) do names[#names + 1] = name end
				table.sort(names)
				ns.Log("zoom", ("  %5.2f %6.2f yd  asked %+6.2f %s  %s%s max %s%s"):format(t - now, trace.z[i], ask,
					#names > 0 and table.concat(names, ",") or "-",
					trace.phase[i] and ("%s/%s"):format(tostring(trace.ctx[i]), trace.phase[i]) or "-", trace.steer[i] and " steering" or "",
					tostring(trace.max[i]), refused and ("  " .. refused) or ""))
				written, lastAt, ask, who, refused = written + 1, t, 0, {}, nil
			end
		end
	end
	return written
end

local function Watch(_, elapsed)
	if not GetCameraZoom then return end
	local now = GetTime()
	local zoom = GetCameraZoom()
	if type(zoom) ~= "number" then return end
	local prev = trace.n > 0 and trace.z[trace.head] or zoom
	Record(now, zoom)
	local ours = now - guard.oursAt < OURS_RECENT
	local yours = now - (ns.lastPlayerZoomAt or -math.huge) < YOURS_RECENT
	-- A jump: the distance changed faster than any zoom goes (the game pulling
	-- the camera in to a lowered max, say). Logged with the trace.
	local dz = zoom - prev
	if not yours and math.abs(dz) >= JUMP_SIZE and math.abs(dz) / math.max(elapsed or 0.016, 0.001) > JUMP_SPEED
		and now - lastJumpLog > 3 then
		lastJumpLog = now
		if ours then ns.Log("zoom", ("zoom guard: the camera jumped %.1f -> %.1f yards in one frame (ours zooming %s, max factor %s)"):format(
			prev, zoom, tostring(ours), tostring(GetCVar("cameraDistanceMaxZoomFactor")))) end
		-- (The trace only with ours zooming, now and then: the game pulls the
		-- camera in past trees and walls all the time.)
		if ours and now - (guard.jumpTraceAt or -math.huge) > SWING_LOG_GAP then
			guard.jumpTraceAt = now
			ns.ZoomTraceDump("jump", 0.5, 0.5)
		end
	end
	if yours then
		-- Yours to move: start afresh from here.
		guard.extreme, guard.dir, guard.turns = zoom, nil, {}
		return
	end
	guard.extreme = guard.extreme or zoom
	local moved = zoom - guard.extreme
	if not guard.dir then
		if math.abs(moved) >= SWING_SIZE then
			guard.dir, guard.extreme = moved > 0 and 1 or -1, zoom
		end
		return
	end
	if (guard.dir > 0 and zoom > guard.extreme) or (guard.dir < 0 and zoom < guard.extreme) then
		guard.extreme = zoom -- still going the same way: the furthest it's got
	elseif math.abs(moved) >= SWING_SIZE then
		-- Back the other way by enough: a turn of direction.
		guard.dir, guard.extreme = -guard.dir, zoom
		local turns = guard.turns
		turns[#turns + 1] = now
		while turns[1] and now - turns[1] > WINDOW do
			table.remove(turns, 1)
		end
		if #turns >= SWINGS then
			-- Ours zooming in that time: hold them. Not ours: the game's own
			-- (camera collision...), logged only.
			local oursLately = now - guard.oursAt < WINDOW
			if oursLately then
				Trip(now, zoom)
				ns.ZoomTraceDump("trip")
			elseif now - lastSwingLog > SWING_LOG_GAP then
				lastSwingLog = now
				guard.turns = {}
				ns.Log("zoom", ("zoom guard: the camera swung in and out %d times in %d sec with no zoom of ours or yours (now %.1f yards, camera %s)"):format(
					SWINGS, WINDOW, zoom, tostring(ns.activeCam or "none")))
				ns.ZoomTraceDump("swings, not ours")
			else
				guard.turns = {}
			end
		end
	end
end

local frame = CreateFrame("Frame")
ns.SetOnUpdate(frame, Watch)
-- A /reload or logout keeps the last 30 sec in the saved log, if one of our
-- zooms ran in that time: a line per quarter second, about 120 (the log keeps 500).
frame:RegisterEvent("PLAYER_LOGOUT")
frame:SetScript("OnEvent", function()
	if GetTime() - guard.oursAt < TRACE_SECS then
		pcall(ns.ZoomTraceDump, "reload or logout", 0.25, 0, TRACE_SECS)
	end
end)

-- For /cine debug zoom.
function ns.ZoomGuardDebug()
	local now = GetTime()
	local held = guard.holdUntil - now
	return ("zoom guard: %s; trips %d%s; turns of direction just now %d; last zoom sent %s"):format(
		held > 0 and ("holding our zooms %.0f more sec"):format(held) or "not holding",
		guard.trips, guard.trips > 0 and (" (last %.0f sec ago, zooming: %s)"):format(now - guard.lastTripAt,
			guard.lastWho ~= "" and guard.lastWho or "?") or "",
		#guard.turns, tostring(guard.lastSent or "none"))
end
